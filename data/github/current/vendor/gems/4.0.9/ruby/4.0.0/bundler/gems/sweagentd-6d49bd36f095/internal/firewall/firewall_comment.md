> [!WARNING]
>
> <details>
> <summary>Firewall rules blocked me from connecting to one or more addresses (expand for details)</summary>
>
> #### I tried to connect to the following addresses, but was blocked by firewall rules:
>
{{- range $key, $blockedRequests := .Locations}}
> - `{{ $key }}`
  {{- range $blockedRequest := $blockedRequests }}
   {{- if $blockedRequest.Cmd }}
>   - Triggering command: `{{ $blockedRequest.Cmd }}` ({{ $blockedRequest.BlockedAt}} block)
   {{- end }} 
  {{- end }}
{{- end}}
>
> If you need me to access, download, or install something from one of these locations, you can either:
>
> - Configure [Actions setup steps](https://gh.io/copilot/actions-setup-steps) to set up my environment, which run before the firewall is enabled
> - Add the appropriate URLs or hosts to the custom allowlist in this repository's [Copilot cloud agent settings]({{.FirewallSettingsLink}}) (admins only)
>
> </details>

<!-- copilot-coding-agent-warning: firewall-blocked -->