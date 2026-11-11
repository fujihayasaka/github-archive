# Accessibility audits and audit findings

Services with an `Accessibility Compliance` scorecard are [audited annually](https://github.com/github/accessibility/blob/main/audit/process.md) for [Microsoft Accessibility Standard grades](https://github.com/github/accessibility-governance/blob/main/policy/MAS-grades.md) including the following services in this repo:

| **Service** | **Scorecard** | **Open Audits** | **Open Audit Findings** | **Conformance Report** | **Tracking Issue**
| ----------- | :-----------: | :-------------: | :---------------------: | :--------------------: | :----------------:
| [`copilot-cli`](https://catalog.githubapp.com/services/copilot-cli/slos) | [scorecard](https://a11y-scorecard.github.com/services/copilot-cli) | [audits](https://github.com/github/accessibility/issues?q=is%3Aissue%20label%3Aservice%3Acopilot-cli) | [findings](https://github.com/github/accessibility-audits/issues?q=is%3Aopen%20label%3Aservice%3Acopilot-cli) | [report](https://accessibility.github.com/conformance/copilot-cli/) | [issue](https://github.com/github/accessibility-governance/issues/2793)

## Need help?

- [`github/accessibility` repository](https://github.com/github/accessibility) for documentation and FAQs
- [`#accessibility` Slack channel](https://slack.com/app_redirect?channel=accessibility) for talking with team

## Essentials

Team members should be familiar with the following for supporting accessibility efforts:

1. [GitHub Accessibility marketing website](https://accessibility.github.com/)

   _This is a public facing marketing site around GitHub's accessibility efforts to inform and guide users including compliance reports and feedback channels._

1. [GitHub Blog _"Building a more accessible GitHub CLI"_ post](https://github.blog/engineering/user-experience/building-a-more-accessible-github-cli/)

   _This is a public blog post that accompanied `gh` public preview of accessibility improvements._

1. Internal Accessibility repositories:
   - [`github/accessibility`](https://github.com/github/accessibility): general information, FAQs, audit issues, and help
   - [`github/accessibility-audits`](https://github.com/github/accessibility-audits): audit finding issues
   - [`github/accessibility-scorecard`](https://github.com/github/accessibility-scorecard): driver behind audits
   - [`github/accessibility-governance`](https://github.com/github/accessibility-governance): source of truth for services and accessibility

1. [Testing Guidelines for the GH Command Line Interface in `github/accessibility-audit-guide`](https://github.com/github/accessibility-audit-guide/tree/main/cli)

   _This is a living document of CLI accessibility guidelines and how they differ from [Web Content Accessibility Guidelines (WCAG)](https://www.w3.org/WAI/standards-guidelines/wcag/)._

1. [Accessibility audit process](https://github.com/github/accessibility/blob/main/audit/process.md)
   - [Handling audit findings](https://github.com/github/accessibility/blob/main/audit/process.md#8-issues-are-handed-off-to-the-service-team)
   - [Closing issues that have been fixed](https://github.com/github/accessibility/blob/main/audit/process.md#closing-issues-that-have-been-fixed)
   - [Closing issues that are no longer relevant or valid](https://github.com/github/accessibility/blob/main/audit/process.md#closing-issues-that-are-no-longer-relevant-or-valid)

1. Check out our current and past audit findings:
   - [`service:copilot-cli`](https://github.com/github/accessibility-audits/issues?q=label%3Aservice%3Acopilot-cli)
