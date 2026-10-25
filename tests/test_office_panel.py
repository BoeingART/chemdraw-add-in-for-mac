# SPDX-License-Identifier: Apache-2.0
import http.client
import json
import re
import ssl
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from install_office import prepare_tls,install,destinations
from office_ui import start_office_ui
import install_office

class PanelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch=tempfile.TemporaryDirectory()
        cls.root=Path(cls.scratch.name)
        assets=cls.root/'office/addin'; assets.mkdir(parents=True)
        (assets/'taskpane.html').write_text('<meta name="cfm-token" content="__CFM_TOKEN__">')
        (assets/'manifest.xml').write_text('<test-manifest/>')
        cert=prepare_tls(cls.root)
        cls.context=ssl.create_default_context(cafile=str(cert))
        cls.jobs=[]
        class Queue:
            def put(_,item):
                cls.jobs.append(item[0]); item[1].set_result(True)
        cls.server=start_office_ui(cls.root,SimpleNamespace(session=None),Queue(),port=0)
        cls.port=cls.server.server_port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.scratch.cleanup()

    def request(self,method,path,body=None,headers=None):
        connection=http.client.HTTPSConnection('localhost',self.port,context=self.context,timeout=3)
        connection.request(method,path,body=body,headers=headers or {})
        response=connection.getresponse(); result=(response.status,response.read()); connection.close()
        return result

    def test_cross_site_and_missing_token_cannot_edit_drawings(self):
        for headers in ({'Origin':'https://unrelated.example'},{}):
            status,_=self.request('POST','/api/edit','{"host":"word"}',headers)
            self.assertEqual(status,403)
        status,_=self.request('GET','/api/status',headers={'Host':'unrelated.example'})
        self.assertEqual(status,403)

    def test_panel_action_queues_only_a_valid_host(self):
        _,html=self.request('GET','/taskpane.html')
        token=re.search(b'content="([^"]+)"',html).group(1).decode()
        headers={'X-ChemOffice-Token':token,'Content-Type':'application/json'}
        status,_=self.request('POST','/api/edit','{"host":"word"}',headers)
        self.assertEqual(status,200)
        self.assertEqual(self.jobs[-1],{'event':'edit-selection','host':'word'})
        status,_=self.request('POST','/api/edit','{"host":"unknown"}',headers)
        self.assertEqual(status,400)

    def test_installer_copies_only_our_manifests_without_touching_security(self):
        home=self.root/'test-home'
        target=destinations(home)[0]
        target.parent.mkdir(parents=True)
        other=target.parent/'another-addin.xml'; other.write_text('keep me')
        install(home=home,root=self.root)
        self.assertEqual(other.read_text(),'keep me')
        for target in destinations(home):self.assertEqual(target.read_text(),'<test-manifest/>')

    def test_protected_containers_produce_a_finder_fallback_not_false_success(self):
        copy=install_office.shutil.copy2
        def protected_copy(source,target):
            if 'Containers' in str(target): raise PermissionError('protected')
            return copy(source,target)
        with patch.object(install_office.shutil,'copy2',side_effect=protected_copy):
            self.assertFalse(install(home=self.root/'protected-home',root=self.root))
        self.assertEqual((self.root/'work/install/chemoffice-for-mac.xml').read_text(),'<test-manifest/>')
