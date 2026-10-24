#!/usr/bin/env python3
"""Render native sample views and assemble README PNG/GIF (requires Pillow)."""
from pathlib import Path
import argparse
import json
import os
import platform
import plistlib
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FRAMES = ROOT / '.build/readme-frames'
ASSETS = ROOT / 'docs/assets'


def render():
    product = ROOT / '.build/readme-core'
    product.mkdir(parents=True, exist_ok=True)
    target = platform.machine()+'-apple-macosx13.0'
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / '.build/clang-cache'))
    core = ['swiftc', '-swift-version', '5', '-target', target, '-emit-module', '-emit-object',
            '-parse-as-library', '-whole-module-optimization', '-module-name', 'CalendarCore',
            '-emit-module-path', str(product / 'CalendarCore.swiftmodule'),
            '-o', str(product / 'CalendarCore.o')]
    core += [str(p) for p in (ROOT / 'Sources/CalendarCore').glob('*.swift')]
    subprocess.run(core, cwd=ROOT, check=True, env=env)
    app = ROOT / '.build/readme-demo.app'
    macos, frameworks = app / 'Contents/MacOS', app / 'Contents/Frameworks'
    macos.mkdir(parents=True, exist_ok=True)
    frameworks.mkdir(exist_ok=True)
    vendor = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    if not vendor.exists():
        subprocess.run([str(ROOT / 'scripts/build-app.sh')], cwd=ROOT, check=True)
    subprocess.run(['ditto', str(vendor), str(frameworks / 'Sparkle.framework')], check=True)
    files = [str(p) for p in (ROOT / 'Sources/PerpetualCalendar').glob('*.swift')
             if p.is_file()]
    command = ['swiftc', '-parse-as-library', '-swift-version', '5', '-target', target, '-I', str(product),
               '-D', 'CALENDAR_CHECKS', '-F', str(frameworks), '-framework', 'Sparkle', '-Xlinker', '-rpath',
               '-Xlinker', '@executable_path/../Frameworks', str(product / 'CalendarCore.o')]
    command += files + [str(ROOT / 'scripts/ReadmeDemo.swift'), '-o', str(macos / 'ReadmeDemo')]
    subprocess.run(command, cwd=ROOT, check=True,
                   env=dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / '.build/clang-cache')))
    info = dict(CFBundleIdentifier='org.menubar-calendar.readme-demo-renderer',
                CFBundleName='Readme demo', CFBundleExecutable='ReadmeDemo', CFBundleVersion='1',
                CFBundlePackageType='APPL', LSUIElement=True, NSPrincipalClass='NSApplication')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    FRAMES.mkdir(parents=True, exist_ok=True)
    for path in FRAMES.glob('frame-*.png'):
        path.unlink()
    subprocess.run([str(macos / 'ReadmeDemo'), str(FRAMES)], check=True)


def font(size, bold=False):
    return ImageFont.truetype('/System/Library/Fonts/STHeiti '+('Medium' if bold else 'Light')+'.ttc', size)


def cover():
    width, height = 1600, 1030
    canvas = Image.new('RGB', (width, height))
    pixels = canvas.load()
    for y in range(height):
        for x in range(width):
            glow = max(0, 1-((x-1160)**2+(y-280)**2)**0.5/1000)
            pixels[x, y] = (int(9+4*glow), int(18+18*glow+y/height*3), int(32+27*glow))
    canvas = canvas.convert('RGBA')
    draw = ImageDraw.Draw(canvas)
    draw.text((70, 124), 'macOS 菜单栏万年历', font=font(19), fill='#92A9C1')
    draw.text((62, 182), '不知时日历', font=font(62, True), fill='#F4F8FF')
    draw.text((70, 340), '时间，抬眼就见。', font=font(31, True), fill='#E5EFFA')
    draw.text((70, 408), '农历 · 节气 · 节假日', font=font(23), fill='#8AD9E0')
    draw.multiline_text((70, 485), '从日常日期到传统时辰，\n把需要的信息放在菜单栏。',
                        font=font(21), fill='#9CAFC4', spacing=14)
    draw.text((70, 636), '免费开源 · 本地存储', font=font(21, True), fill='#ECF4FF')
    draw.rounded_rectangle((70, 694, 224, 738), radius=22, fill='#203249', outline='#354C65')
    draw.text((91, 706), 'macOS 13+', font=font(18), fill='#C8D6E7')
    draw.text((70, 781), 'Intel 与 Apple Silicon', font=font(18), fill='#8DA5BF')
    draw.text((70, 815), 'MIT License', font=font(18), fill='#8DA5BF')
    for name, x, label in [('light', 480, '浅色主题'), ('dark', 1010, '深色主题')]:
        y = 154
        shadow = Image.new('RGBA', canvas.size)
        sd = ImageDraw.Draw(shadow)
        sd.rounded_rectangle((x-5, y+12, x+425, y+774), radius=28, fill=(0, 0, 0, 125))
        canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(24)))
        panel = Image.open(FRAMES / f'calendar-{name}.png').convert('RGBA')
        panel = Image.alpha_composite(Image.new('RGBA', panel.size, '#FAFAFA' if name == 'light' else '#131313'), panel)
        mask = Image.new('L', panel.size)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, 419, 749), radius=22, fill=255)
        canvas.paste(panel, (x, y), mask)
        ImageDraw.Draw(canvas).text((x+3, y-39), label, font=font(18), fill='#92A9C1')
    ImageDraw.Draw(canvas).text((480, 946), '原生界面预览 · 示例日期', font=font(15), fill='#6F879F')
    canvas.convert('RGB').save(ASSETS / 'hero.png', optimize=True)



def animation():
    timeline = json.loads((FRAMES / 'frames.json').read_text())
    assert set(frame['stage'] for frame in timeline) == set(range(13)), 'Incomplete demonstration'
    paths = [FRAMES / frame['file'] for frame in timeline]
    frames = []
    for path in paths:
        image = Image.open(path).convert('RGBA')
        # AppKit cacheDisplay leaves composited scroll-view backgrounds clear.
        dark = sum(image.getpixel((5, 5))[:3]) < 300
        background = Image.new('RGBA', image.size, '#131313' if dark else '#FAFAFA')
        frames.append(Image.alpha_composite(background, image).convert('RGB'))
    samples = frames[::max(1, len(frames)//16)]
    sheet = Image.new('RGB', (480*4, 434*4))
    for i, frame in enumerate(samples[:16]):
        sheet.paste(frame.resize((480, 434)), ((i%4)*480, (i//4)*434))
    palette = sheet.quantize(colors=256)
    quantized = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    durations = [max(40, min(160, round((timeline[i+1]['time']-frame['time'])*100)*10))
                 for i, frame in enumerate(timeline[:-1])] + [900]
    quantized[0].save(ASSETS / 'demo.gif', save_all=True, append_images=quantized[1:],
                      duration=durations, loop=0, disposal=1, optimize=True)
    print('Native frames:', len(frames))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-render', action='store_true')
    args = parser.parse_args()
    ASSETS.mkdir(parents=True, exist_ok=True)
    if not args.skip_render:
        render()
    cover()
    animation()
    for name in ('hero.png', 'demo.gif'):
        path = ASSETS / name
        print(name, f'{path.stat().st_size/1024/1024:.2f} MiB')
