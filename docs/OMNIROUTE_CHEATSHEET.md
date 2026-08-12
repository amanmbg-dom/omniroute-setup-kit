# OmniRoute — One-Page Cheat Sheet

*Server: `http://localhost:20128` · Dashboard: `/admin` · Auth: `Bearer omniroute` (local) · Full guide: `OMNIROUTE_GUIDE.md`*

## Run & check

```bash
omniroute                  # start server (gateway + dashboard)
omniroute status           # everything at a glance
omniroute health           # component health
omniroute doctor           # diagnose providers/ports/deps
omniroute dashboard        # open web UI
omniroute stop | restart   # stop / restart
```

## Chat & route

```bash
omniroute chat "hi" -m auto                # one-shot chat
omniroute stream "hi"                      # streaming chat
omniroute repl                             # interactive chat
omniroute simulate "hi"                    # dry-run: who WOULD answer (no cost)
omniroute test <provider> <model>          # live test
```

## Providers & keys

```bash
omniroute providers available              # catalog (290+)
omniroute providers list                   # your connections
omniroute providers test-all               # test everything
omniroute providers status                 # key health (age/expiry/cooldown)
omniroute providers metrics                # latency/success/cost
omniroute providers rotate <id>            # new upstream key
omniroute keys add <provider> <key>        # add key
omniroute keys list                        # keys (masked)
omniroute oauth start                      # browser OAuth connect
omniroute nodes list                       # provider endpoint nodes
```

## Models & combos

```bash
omniroute models --search nemotron         # find models
omniroute combo list | switch <name>       # list / activate combo
omniroute combo create <name>              # build a combo
omniroute combo suggest                    # AI-recommended combo
# auto → balanced · auto/coding · auto/fast · auto/cheap · auto/offline
```

## Money & usage

```bash
omniroute cost --group-by provider         # cost report
omniroute usage analytics                  # usage analytics
omniroute usage budget                     # set budgets
omniroute quota                            # free-tier quota left
omniroute pricing list                     # model pricing
omniroute telemetry summary                # aggregated telemetry
```

## Performance

```bash
omniroute compression status               # compression on?
omniroute compression configure            # set preset (lite→ultra, RTK)
omniroute compression preview "..."        # see savings on a prompt
omniroute cache status | clear             # response cache
omniroute resilience status                # breakers/cooldowns/lockouts
omniroute resilience reset                 # clear them
```

## Memory, skills, evals

```bash
omniroute memory search "q" | memory add   # semantic memory (opt-in)
omniroute skills list | install <path>     # skills
omniroute eval suites | run <suiteId>      # evals
```

## Automation & protocols

```bash
omniroute webhooks list | add              # push events to URLs
omniroute files upload <path>              # file storage
omniroute batches submit <file.jsonl>      # batch jobs
omniroute translator translate <in> <out>  # convert API formats
omniroute openapi endpoints                # list API endpoints
omniroute api chat --help                  # REST access
omniroute --mcp                            # MCP server (stdio)
omniroute a2a                              # agent-to-agent server
```

## Remote, sync, tunnels

```bash
omniroute connect <host>                   # CLI → remote server
omniroute contexts list | use <name>       # switch server profiles
omniroute tokens create --scope admin      # scoped remote tokens
omniroute sync push | pull | diff          # sync config
omniroute sync bundle out.json             # export config file
omniroute sync import in.json              # import on another machine
omniroute tunnel create tailscale          # expose to other devices
```

## Tool setup (one command each)

```bash
omniroute setup-claude | setup-codex | setup-opencode | setup-cline
omniroute setup-kilo | setup-roo | setup-continue | setup-cursor
omniroute setup-goose | setup-aider | setup-qwen | setup-crush
omniroute launch                          # start Claude Code → OmniRoute
omniroute configure codex                 # pick model, write config
```

## Ops & safety

```bash
omniroute backup create                   # snapshot data
omniroute restore <id>                    # restore
omniroute audit tail                      # audit log
omniroute policy list                     # authorization policies
omniroute env show                        # env vars
omniroute runtime check                   # native deps
omniroute autostart enable                # start at login
omniroute update                          # self-update
```

## Global flags

```bash
--output json | csv | jsonl               # scriptable output
-q, --quiet                               # less noise
--base-url <url> · --api-key <key>        # target another server
--context <name>                          # server profile
```

## Quick fixes

| Problem | Fix |
|---|---|
| Connection refused | Server not running → `omniroute` |
| `401 User not found` | Web-session expired → refresh cookies / reconnect |
| `429` rate limit | Normal; resilience cools it — use `auto` |
| Token burn | `omniroute compression configure` |
| Localhost fails on Windows | Use `127.0.0.1` (server binds IPv4 only) |
| Port busy | `omniroute status`, kill other instance, or change `PORT` |
