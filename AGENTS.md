## MANDATORY PROJECT RULES

### Secrets in ArgoCD applications

- NEVER read, open, list, grep, diff, copy, or otherwise inspect anything under `continuous-deployment/argo/`. Those files are gitignored and can contain live service tokens.
- When a change requires edits there (for example bumping `targetRevision` or toggling a value), do not make them. Tell the user exactly which application and field to change, and let the user do it.
- Do not run scripts that read or print that folder (for example `continuous-deployment/export-helm-to-argo.sh`) unless the user explicitly asks.
