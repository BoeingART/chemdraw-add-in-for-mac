# SPDX-License-Identifier: Apache-2.0
"""Check catalog coverage and consistency across distributable surfaces."""
import csv
import io
import json
from pathlib import Path
import plistlib
import re
import subprocess
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / 'localization/strings.json').read_text())


class LocalizationTests(unittest.TestCase):
    def test_generated_resources_match_catalog(self):
        subprocess.run(['python3', str(ROOT / 'scripts/localize.py'), '--check'],check=True)

    def test_native_and_panel_keys_exist(self):
        for path in (ROOT / 'src').glob('*.swift'):
            if path.name == 'NativeStrings.swift':
                continue
            for key in re.findall(r'\bL\("([^"]+)"',path.read_text()):
                self.assertIn(key,CATALOG,str(path))
        html = (ROOT / 'office/addin/taskpane.html').read_text()
        for key in re.findall(r'__CFM_TEXT_([^_]+)__',html):
            self.assertIn(key,CATALOG)
        for key in re.findall(r"\bt\('([^']+)'",(ROOT / 'office/addin/taskpane.js').read_text()):
            self.assertIn('pane.'+key,CATALOG)

    def test_every_owned_applescript_error_has_a_translation(self):
        errors = {entry['script_error'] for entry in CATALOG.values() if 'script_error' in entry}
        paths = [ROOT / 'src/NativeAutomation.swift', *ROOT.glob('office/*/adapter.applescript')]
        for path in paths:
            for text in re.findall(r'\berror "([^"\n]+)"',path.read_text()):
                self.assertIn(text,errors,str(path))

    def test_catalog_has_both_languages_and_matching_parameters(self):
        for key,entry in CATALOG.items():
            self.assertTrue(entry['en'] and entry['zh'] and entry['locations'],key)
            self.assertFalse(re.search(r'[\u4e00-\u9fff]',entry['en']),key)
            self.assertEqual(sorted(re.findall(r'\{\d+\}',entry['en'])),sorted(re.findall(r'\{\d+\}',entry['zh'])),key)

    def test_review_table_contains_every_entry_once(self):
        review = (ROOT / 'docs/ui-strings-review.html').read_text()
        self.assertEqual(len(re.findall(r'<tr data-key=',review)),len(CATALOG))
        self.assertEqual(set(re.findall(r'<tr data-key="([^"]+)"',review)),set(CATALOG))
        with (ROOT / 'docs/ui-strings.tsv').open(newline='') as file:
            rows = list(csv.DictReader(file,delimiter='\t'))
        self.assertEqual(len(rows),len(CATALOG))
        for row in rows:
            self.assertEqual(row['中文'],CATALOG[row['文案ID']]['zh'])
            self.assertEqual(row['英文'],CATALOG[row['文案ID']]['en'])

    def test_system_usage_description_is_packaged_in_both_languages(self):
        info = plistlib.loads((ROOT / 'packaging/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleDevelopmentRegion'],'en')
        for language in ['en','zh-Hans','zh-Hant']:
            self.assertIn(language,info['CFBundleLocalizations'])
            resource = ROOT / f'packaging/{language}.lproj/InfoPlist.strings'
            self.assertIn('NSAppleEventsUsageDescription',resource.read_text())
        package = (ROOT / 'scripts/package.sh').read_text()
        self.assertIn('packaging/zh-Hans.lproj',package)
        self.assertIn('packaging/Install.txt',package)
        self.assertIn('universal.zip',package)
        self.assertIn('universal.dmg',package)

    def test_installer_pages_are_localized_and_concise(self):
        for folder,language in [('en','en'),('zh_CN','zh'),('zh_TW','zh'),('zh_HK','zh')]:
            for page in ['Welcome','Conclusion']:
                text = (ROOT / f'packaging/{folder}.lproj/{page}.html').read_text()
                self.assertNotRegex(text.lower(),r'sha256|checksum|fingerprint|哈希|校验和|指纹')
                self.assertNotRegex(text,r'不代表|不意味着|不保证|不代替')
                if language == 'en':
                    self.assertNotRegex(text,r'[\u4e00-\u9fff]')
                else:
                    self.assertIn('加载项',text)
        ET.parse(ROOT / 'office/addin/manifest.xml')


if __name__ == '__main__':
    unittest.main(verbosity=2)
