import os
import json
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

def generate_assets():
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    assets_dir = os.path.join(project_root, 'assets')
    icons_dir = os.path.join(assets_dir, 'icons')
    ios_dir = os.path.join(icons_dir, 'ios', 'AppIcon.appiconset')
    os.makedirs(icons_dir, exist_ok=True)
    os.makedirs(ios_dir, exist_ok=True)

    src_path = os.path.join(assets_dir, 'Logo Pita Biru Ungu Berkilau.png')
    if not os.path.exists(src_path):
        raise FileNotFoundError(f'Source logo not found at {src_path}')

    print(f'Loading source logo from: {src_path}')
    img = Image.open(src_path).convert('RGBA')
    arr = np.array(img)
    # Clean alpha noise (<= 4)
    arr[arr[:, :, 3] <= 4, 3] = 0

    # Find tight bounding box of logo symbol
    alpha = arr[:, :, 3]
    rows = np.any(alpha > 4, axis=1)
    cols = np.any(alpha > 4, axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]

    cropped = arr[rmin:rmax+1, cmin:cmax+1]
    crop_h, crop_w = cropped.shape[:2]
    cropped_img = Image.fromarray(cropped)
    print(f'Cropped logo size: {crop_w} x {crop_h}')

    # 1. Generate Adaptive Icon Foreground (1024x1024)
    # Balanced scale: target_h = 680 px (W = 576 px), centered at (512, 512)
    # Guarantees 0.00% clipping on 72dp circle viewport while maximizing size
    target_h = 680
    target_w = int(round(crop_w * (target_h / crop_h)))
    scaled_logo = cropped_img.resize((target_w, target_h), Image.Resampling.LANCZOS)

    fg_1024 = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    ox = (1024 - target_w) // 2
    oy = (1024 - target_h) // 2
    fg_1024.paste(scaled_logo, (ox, oy), scaled_logo)
    fg_path = os.path.join(icons_dir, 'adaptive_foreground.png')
    fg_1024.save(fg_path)
    print(f'Saved: {fg_path}')

    # 2. Generate Adaptive Icon Background (1024x1024)
    # Soft lavender #F0EEFF (240, 238, 255)
    bg_1024 = Image.new('RGBA', (1024, 1024), (240, 238, 255, 255))
    bg_path = os.path.join(icons_dir, 'adaptive_background.png')
    bg_1024.save(bg_path)
    print(f'Saved: {bg_path}')

    # 3. Generate Main App Icon (1024x1024)
    main_icon = Image.alpha_composite(bg_1024, fg_1024)
    main_path = os.path.join(icons_dir, 'app_icon.png')
    main_icon.save(main_path)
    print(f'Saved: {main_path}')

    # 4. Generate Adaptive Monochrome Icon (1024x1024) for Themed Icons (Android 13+)
    fg_arr = np.array(fg_1024)
    outer_mask = fg_arr[:, :, 3] > 20

    # Draw scaled pill mask
    pill_mask = Image.new('L', (1024, 1024), 0)
    draw_pill = ImageDraw.Draw(pill_mask)
    cx_center = 512.0
    cy_center = 521.0
    pill_w = 296.0
    pill_h = 150.0
    rad = pill_h / 2.0
    px0 = cx_center - pill_w / 2.0
    py0 = cy_center - pill_h / 2.0
    px1 = cx_center + pill_w / 2.0
    py1 = cy_center + pill_h / 2.0
    draw_pill.rounded_rectangle([px0, py0, px1, py1], radius=rad, fill=255)
    pill_arr = np.array(pill_mask) > 128

    # Draw scaled dots mask
    dots_mask = Image.new('L', (1024, 1024), 0)
    draw_dots = ImageDraw.Draw(dots_mask)
    dot_r = 25.0
    dx = 76.0
    for cx in [cx_center - dx, cx_center, cx_center + dx]:
        draw_dots.ellipse([cx - dot_r, cy_center - dot_r, cx + dot_r, cy_center + dot_r], fill=255)
    dots_arr = np.array(dots_mask) > 128

    mono_arr = outer_mask.copy()
    mono_arr[pill_arr] = False
    mono_arr[dots_arr] = True

    mono_img = Image.fromarray((mono_arr.astype(np.uint8) * 255), mode='L')
    mono_smooth = mono_img.filter(ImageFilter.GaussianBlur(radius=1.2))

    mono_1024 = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
    mono_1024.putalpha(mono_smooth)
    mono_path = os.path.join(icons_dir, 'adaptive_monochrome.png')
    mono_1024.save(mono_path)
    print(f'Saved: {mono_path}')

    # 5. Generate iOS AppIcon Pack (assets/icons/ios/AppIcon.appiconset/)
    ios_sizes = [
        ('Icon-App-1024x1024@1x.png', 1024),
        ('Icon-App-60x60@3x.png', 180),
        ('Icon-App-60x60@2x.png', 120),
        ('Icon-App-76x76@2x.png', 152),
        ('Icon-App-76x76@1x.png', 76),
        ('Icon-App-83.5x83.5@2x.png', 167),
        ('Icon-App-40x40@3x.png', 120),
        ('Icon-App-40x40@2x.png', 80),
        ('Icon-App-40x40@1x.png', 40),
        ('Icon-App-29x29@3x.png', 87),
        ('Icon-App-29x29@2x.png', 58),
        ('Icon-App-29x29@1x.png', 29),
        ('Icon-App-20x20@3x.png', 60),
        ('Icon-App-20x20@2x.png', 40),
        ('Icon-App-20x20@1x.png', 20),
    ]

    for filename, sz in ios_sizes:
        resized_ios = main_icon.resize((sz, sz), Image.Resampling.LANCZOS)
        out_p = os.path.join(ios_dir, filename)
        resized_ios.save(out_p)

    # iOS 18 Dark & Tinted Master Icons (1024x1024)
    # Dark variant: Dark slate background (#13151A)
    ios_dark_bg = Image.new('RGBA', (1024, 1024), (19, 21, 26, 255))
    ios_dark = Image.alpha_composite(ios_dark_bg, fg_1024)
    ios_dark.save(os.path.join(ios_dir, 'Icon-App-Dark-1024x1024.png'))

    # Tinted variant: Dark slate background with monochrome silhouette
    ios_tinted_sym = Image.new('RGBA', (1024, 1024), (230, 225, 250, 255))
    ios_tinted_sym.putalpha(mono_smooth)
    ios_tinted = Image.alpha_composite(ios_dark_bg, ios_tinted_sym)
    ios_tinted.save(os.path.join(ios_dir, 'Icon-App-Tinted-1024x1024.png'))

    # Contents.json for Xcode catalog
    contents_dict = {
        "images": [
            {"size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@2x.png", "scale": "2x"},
            {"size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@3x.png", "scale": "3x"},
            {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@2x.png", "scale": "2x"},
            {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@3x.png", "scale": "3x"},
            {"size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@2x.png", "scale": "2x"},
            {"size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@3x.png", "scale": "3x"},
            {"size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@2x.png", "scale": "2x"},
            {"size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@3x.png", "scale": "3x"},
            {"size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@1x.png", "scale": "1x"},
            {"size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@2x.png", "scale": "2x"},
            {"size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@1x.png", "scale": "1x"},
            {"size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@2x.png", "scale": "2x"},
            {"size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@1x.png", "scale": "1x"},
            {"size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@2x.png", "scale": "2x"},
            {"size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@1x.png", "scale": "1x"},
            {"size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@2x.png", "scale": "2x"},
            {"size": "83.5x83.5", "idiom": "ipad", "filename": "Icon-App-83.5x83.5@2x.png", "scale": "2x"},
            {"size": "1024x1024", "idiom": "ios-marketing", "filename": "Icon-App-1024x1024@1x.png", "scale": "1x"}
        ],
        "info": {
            "version": 1,
            "author": "xcode"
        }
    }
    with open(os.path.join(ios_dir, 'Contents.json'), 'w', encoding='utf-8') as f:
        json.dump(contents_dict, f, indent=2)
    print(f'Saved iOS AppIcon catalog: {ios_dir}')

    # 6. Generate Android Monochrome Drawables & Mipmaps
    # Android 108dp adaptive canvas density dimensions:
    # mdpi: 108x108
    # hdpi: 162x162
    # xhdpi: 216x216
    # xxhdpi: 324x324
    # xxxhdpi: 432x432
    android_res_dir = os.path.join(project_root, 'android', 'app', 'src', 'main', 'res')
    mono_densities = {
        'mdpi': 108,
        'hdpi': 162,
        'xhdpi': 216,
        'xxhdpi': 324,
        'xxxhdpi': 432,
    }

    for density, dim in mono_densities.items():
        drawable_dir = os.path.join(android_res_dir, f'drawable-{density}')
        os.makedirs(drawable_dir, exist_ok=True)
        out_mono = mono_1024.resize((dim, dim), Image.Resampling.LANCZOS)
        target_drawable = os.path.join(drawable_dir, 'ic_launcher_monochrome.png')
        out_mono.save(target_drawable)
        print(f'Saved Android monochrome drawable: {target_drawable} ({dim}x{dim})')

        # Also save in mipmap folder for redundancy
        mipmap_dir = os.path.join(android_res_dir, f'mipmap-{density}')
        os.makedirs(mipmap_dir, exist_ok=True)
        target_mipmap = os.path.join(mipmap_dir, 'launcher_icon_monochrome.png')
        out_mono.save(target_mipmap)

    # 7. Create/Update Adaptive Icon XMLs:
    # A. API 26+ (Android 8.0 - 12): background + foreground
    v26_dir = os.path.join(android_res_dir, 'mipmap-anydpi-v26')
    os.makedirs(v26_dir, exist_ok=True)
    v26_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <background android:drawable="@drawable/ic_launcher_background"/>\n'
        '  <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    with open(os.path.join(v26_dir, 'launcher_icon.xml'), 'w', encoding='utf-8') as f:
        f.write(v26_xml)

    # B. API 33+ (Android 13+ Themed Icons): background + foreground + monochrome
    v33_dir = os.path.join(android_res_dir, 'mipmap-anydpi-v33')
    os.makedirs(v33_dir, exist_ok=True)
    v33_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <background android:drawable="@drawable/ic_launcher_background"/>\n'
        '  <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        '  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n'
    )
    with open(os.path.join(v33_dir, 'launcher_icon.xml'), 'w', encoding='utf-8') as f:
        f.write(v33_xml)
    print(f'Saved Adaptive Icon XMLs for API 26 and API 33 (Themed Icons)')

if __name__ == '__main__':
    generate_assets()
