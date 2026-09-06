<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

<!-- 以下在 SPECTRA 區塊之外，spectra update 不會覆蓋 -->

## Repo layout

```
App/       iPad app — implementation constraints live in App/CLAUDE.md, read it first
Server/    docker-compose for the local SMART launcher (dev auth server)
openspec/  Spectra specs and change proposals
```

**Read `App/CLAUDE.md` before touching any code** — it carries the constraints that bite
repeatedly (the `FHIR.` namespace, Swift Testing's `.serialized` scope, the launcher's `sim`
path segment, the localization workflow).

`openspec/specs/` is what the app actually does — one spec per capability, kept in sync by
`spectra archive`. Read it rather than inferring intent from the code.
