"""Unit test for the simdref rass preset (simdref-rass.py).

Run with the rass venv python, which provides rassumfrassum:
  /opt/rass/bin/python test/test_simdref_rass.py
"""

import asyncio
import importlib.util
import unittest
from pathlib import Path
from types import SimpleNamespace

from rassumfrassum.frassum import LspLogic, PayloadItem, Server

PRESET = Path(__file__).resolve().parent.parent / "simdref-rass.py"


def load_preset():
    """Load simdref-rass.py the way rass loads a preset file."""
    spec = importlib.util.spec_from_file_location("_preset_module", PRESET)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stub_servers():
    """Three stub servers: simdref, clangd and one without hover."""
    simdref = Server(name="simdref-lsp", caps={"hoverProvider": True,
                                               "definitionProvider": True})
    clangd = Server(name="clangd", caps={"hoverProvider": True,
                                         "definitionProvider": True})
    other = Server(name="other", caps={"definitionProvider": True})
    return simdref, clangd, other


def make(cls, servers):
    """Build a logic instance over stub SERVERS."""
    return cls(servers, None, None, None, None,
               SimpleNamespace(stream_diagnostics=False))


class SimdrefRassPresetTest(unittest.TestCase):
    """Check hover routing and the hover merge of the preset."""

    def setUp(self):
        self.module = load_preset()
        self.logic_class = self.module.logic_class()
        self.simdref, self.clangd, self.other = stub_servers()
        self.servers = [self.simdref, self.clangd, self.other]
        self.logic = make(self.logic_class, self.servers)

    def test_logic_class_is_lsp_logic_subclass(self):
        """logic_class() returns a LspLogic subclass, like rass expects."""
        self.assertTrue(issubclass(self.logic_class, LspLogic))

    def test_preset_defines_no_servers(self):
        """A preset without servers() loads; the -- servers stay the only ones."""
        self.assertFalse(hasattr(self.module, "servers"))
        self.assertIs(self.module.logic_class(), self.logic_class)

    def test_hover_routes_to_all_hover_servers(self):
        """Hover goes to every server that declares hoverProvider."""
        got = asyncio.run(self.logic.on_client_request(
            "textDocument/hover", {}, self.servers))
        self.assertEqual(got, [self.simdref, self.clangd])

    def test_other_methods_unchanged(self):
        """textDocument/definition routes exactly like the base class."""
        base = make(LspLogic, self.servers)
        for method in ("textDocument/definition", "textDocument/documentSymbol"):
            want = asyncio.run(base.on_client_request(method, {}, self.servers))
            got = asyncio.run(self.logic.on_client_request(method, {}, self.servers))
            self.assertEqual(got, want, method)

    def test_hover_prefers_the_primary_answer(self):
        """When both answer, the simdref page wins, in any arrival order."""
        mine = {"contents": {"kind": "markdown", "value": "VADDPS"}}
        theirs = {"contents": {"kind": "markdown", "value": "function add"}}
        both = [PayloadItem(mine, self.simdref, False),
                PayloadItem(theirs, self.clangd, False)]
        for items in (both, list(reversed(both))):
            res, is_error = self.logic.process_responses("textDocument/hover",
                                                         items)
            self.assertIs(is_error, False)
            self.assertEqual(res, mine)

    def test_hover_falls_back_to_the_companion(self):
        """A null simdref hover keeps the clangd answer (the C++ name case)."""
        theirs = {"contents": {"kind": "markdown", "value": "function add"}}
        items = [PayloadItem(None, self.simdref, False),
                 PayloadItem(theirs, self.clangd, False)]
        res, is_error = self.logic.process_responses("textDocument/hover", items)
        self.assertIs(is_error, False)
        self.assertEqual(res, theirs)


if __name__ == "__main__":
    unittest.main()
