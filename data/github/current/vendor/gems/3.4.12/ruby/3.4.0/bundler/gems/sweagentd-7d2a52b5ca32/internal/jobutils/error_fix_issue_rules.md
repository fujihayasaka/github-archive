@{{ .Login }} I hit the following errors while trying to work on issue #{{.IssueNumber }}.
{{range .RulesResult.Rules}}
- {{.}}{{end}}
{{if or .RulesResult.HasBranchProtectionRules .RulesResult.HasRepositoryRules}}
> [!NOTE]
> {{if .RulesResult.HasBranchProtectionRules}}- To learn about managing branch protection rules, head to the [GitHub Docs](https://gh.io/copilot-coding-agent-branch-protections). You can resolve this error by migrating from branch protection rules to [rulesets](https://gh.io/copilot-coding-agent-rulesets), and excluding branches beginning with `copilot/`.{{end}}
> {{if .RulesResult.HasRepositoryRules}}- You can resolve this error by excluding branches beginning with `copilot/` from your repository rules. To learn about managing repository rules, head to the [GitHub Docs](https://gh.io/copilot-coding-agent-rulesets).{{end}}
{{end}}

After resolving these issues, you can ask me to try again by unassigning and then reassigning the issue to me again.

{{.Telemetry}}