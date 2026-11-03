"""rass preset for simdref: hover from every server that supports it."""

from rassumfrassum.frassum import LspLogic, PayloadItem, Server
from rassumfrassum.json import JSON


class SimdrefLogic(LspLogic):
    """Send textDocument/hover to every server that has hoverProvider."""

    async def on_client_request(
        self, method: str, params: JSON, servers: list[Server]
    ) -> list[Server]:
        if method == 'textDocument/hover':
            return [
                s for s in servers if s.caps.get('hoverProvider') is not None
            ]
        return await super().on_client_request(method, params, servers)

    def process_responses(
        self, method: str, items: list[PayloadItem]
    ) -> tuple[JSON | list, bool]:
        if method == 'textDocument/hover':
            # Answers arrive in response order and the first item wins
            # the merge, so the pick must not depend on arrival: the
            # primary is simdref-lsp and its instruction page must win
            # over the clangd text on asm lines.  A lone answer survives.
            ok = [i for i in items if not i.is_error and i.payload]
            if ok:
                pick = next((i for i in ok if i.server is self.primary), ok[0])
                return pick.payload, False
        return super().process_responses(method, items)


def logic_class():
    """Return the SimdrefLogic class."""
    return SimdrefLogic
