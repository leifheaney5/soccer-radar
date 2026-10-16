"""Keep the native iOS design system in step with the web dashboard tokens."""

import json
import plistlib
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IOS_ROOT = ROOT / 'clients' / 'ios'
THEME = IOS_ROOT / 'SoccerScanner' / 'DesignSystem' / 'Theme.swift'
BASE_CSS = ROOT / 'static' / 'css' / 'base.css'


def _css_tokens():
    root_block = re.search(r':root\s*\{(.*?)\}', BASE_CSS.read_text(encoding='utf-8'), re.S)
    assert root_block, 'base.css has no :root token block'
    return {
        name: value.upper()
        for name, value in re.findall(r'--([a-z-]+):\s*#([0-9A-Fa-f]{6})\s*;', root_block.group(1))
    }


def _swift_palette():
    block = re.search(r'enum Palette \{(.*?)\n    \}', THEME.read_text(encoding='utf-8'), re.S)
    assert block, 'Theme.swift has no Palette enum'
    return dict(re.findall(r'static let (\w+) = Color\(hex: 0x([0-9A-F]{6})\)', block.group(1)))


def _camel(token):
    head, *rest = token.split('-')
    return head + ''.join(part.title() for part in rest)


def test_native_palette_matches_every_web_colour_token():
    css = _css_tokens()
    palette = _swift_palette()

    assert css, 'no colour tokens parsed from base.css'
    expected = {_camel(name): value for name, value in css.items()}
    assert palette == expected


def test_accent_asset_matches_the_web_accent():
    contents = json.loads(
        (IOS_ROOT / 'SoccerScanner' / 'Resources' / 'Assets.xcassets'
         / 'AccentColor.colorset' / 'Contents.json').read_text(encoding='utf-8')
    )
    accent = _css_tokens()['accent-primary']

    assert contents['colors'], 'AccentColor has no colour entries'
    for entry in contents['colors']:
        components = entry['color']['components']
        rgb = ''.join(f"{int(components[key], 16):02X}" for key in ('red', 'green', 'blue'))
        assert rgb == accent


def test_launch_screen_is_black_like_the_web_shell():
    info = plistlib.loads((IOS_ROOT / 'SoccerScanner' / 'Info.plist').read_bytes())
    name = info['UILaunchScreen']['UIColorName']
    contents = json.loads(
        (IOS_ROOT / 'SoccerScanner' / 'Resources' / 'Assets.xcassets'
         / f'{name}.colorset' / 'Contents.json').read_text(encoding='utf-8')
    )
    components = contents['colors'][0]['color']['components']
    rgb = ''.join(f"{int(components[key], 16):02X}" for key in ('red', 'green', 'blue'))

    assert rgb == _css_tokens()['bg-primary']


def test_brand_font_is_bundled_registered_and_licensed():
    info = plistlib.loads((IOS_ROOT / 'SoccerScanner' / 'Info.plist').read_bytes())
    project = (IOS_ROOT / 'project.yml').read_text(encoding='utf-8')

    assert info['UIAppFonts'] == ['Orbitron-Variable.ttf']
    assert '- Orbitron-Variable.ttf' in project, 'project.yml must declare the same UIAppFonts'
    for resource in ('Tools/fonts/Orbitron-Variable.ttf', 'Tools/fonts/OFL.txt'):
        assert (IOS_ROOT / resource).is_file()
        assert re.search(
            rf'- path: {re.escape(resource)}\s*\n\s*buildPhase: resources', project
        ), f'{resource} is not bundled as an app resource'
    assert '.custom("Orbitron"' in THEME.read_text(encoding='utf-8')


def test_app_root_forces_the_web_dark_appearance():
    app = (IOS_ROOT / 'SoccerScanner' / 'App' / 'SoccerScannerApp.swift').read_text(encoding='utf-8')

    assert '.preferredColorScheme(.dark)' in app
    assert 'Theme.applyAppearance()' in app
