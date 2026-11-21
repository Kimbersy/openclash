# Kimbersy/openclash — repo instructions

**Repository nature**: Public personal Clash configuration, generated client artifacts and device-safe scripts; **NOT** official OpenClash upstream. This is not the canonical location for private household operational logs or Cloudflare secrets.

## Read before any work

1. Private unified entry (authorized account required): https://github.com/Kimbersy/home-it-index/blob/main/docs/clash/README.md
2. Private authoritative OpenClash task: https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_CURRENT_WORK.md
3. Private AI P0 acceptance contract: https://github.com/Kimbersy/home-it-index/blob/main/docs/OPENCLASH_AI_P0_ACCEPTANCE_CONTRACT.md
4. For Cloudflare Worker deployments, **different private repository**: https://github.com/Kimbersy/clash-config-worker and its `AGENTS.md` + `docs/CURRENT_WORK.md`.

The private source of truth may not be accessible without authorization. **Never replace it with guesses.** Local Git content and CI prove source only. Router, ClashMate, Cloudflare and live routing acceptance require separately documented dated receipts.

## Guardrails

- Preserve active `Clash-Li.ini`, generated Android/Shadowrocket, Xbox/AI/Telegram/other normal groups and public Raw consumers unless a specific reviewed modification authorizes changes.
- Do not publish airport URLs, KV/Worker tokens, passwords, full node connection definitions, private traffic logs, source-IP details or house network mappings. This public repository already contains historical maintenance background; audit and sanitize **future** content. Moving/removing files does not purge Git history or outside copies.
- Do not turn this repository private until current public raw file/CI/client/Worker callers and an authenticated or public-template replacement are verified and specifically approved.
- No automatic production deployments or `curl | sh` instructions from an unfixed main ref; use immutable commit SHA, review actual scripts, dependency gate, backups, rollback and separate device acceptance.
- iStoreOS/OpenWrt may lack common Ruby standard libraries: `psych` was observed working while `timeout` was unavailable. Don't assume Ubuntu CI proves router runtime compatibility; use BusyBox shell or only verified router dependencies.
- Avoid unbounded diagnostic loops or a second watcher/service. Reuse historical scripts and device receipts, especially 2026-11-21 AnyTLS fix, instead of reinstalling an already successful patch.
- Cloudflare source, production binding, staged release and rollback must stay in `Kimbersy/clash-config-worker`; no GitHub changes here automatically modify the production Worker.

## Record results

At every material transition, update the private indexed authoritative task and read back that default-branch record; keep fixed Git commit, CI, actual device operation, health, business acceptance and sole next step distinct. If private index cannot be updated, report which data was not saved and do not claim synchronization.

**Known accepted result**: 2026-11-21 A01 AnyTLS SNI 5/5 in 18080, auto-refresh ACK, and user-confirmed ClashMate connection PASS. Independent AI P0 remains open.
