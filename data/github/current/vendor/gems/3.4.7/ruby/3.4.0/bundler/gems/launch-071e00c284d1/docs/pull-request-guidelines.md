# Pull Request Guidelines

This is a supplementary resource to the [Pull Request template](../.github/PULL_REQUEST_TEMPLATE.md)
and should be reviewed by anyone new to Launch.

New pull request reviewers should also read [Guide: Reviewing pull requests](https://thehub.github.com/guides/.reviewing-prs/).

## Checklist

When creating pull requests, please make sure you have considered:

- [ ]💰 GHES - Do we need to update configuration in the `enterprise2` repository? Did you consider the different ways of receiving webhooks?
- [ ] If environment variables are changed, please review [Nomad Config Changes](./nomad.md)
- [ ] 🕵️‍♂️ Error messages, payloads and stack traces do not contain [sensitive information](./secure-exceptions.md#identifying-your-sensitive-data).
- [ ] ⚒️ Compatibility - Did you add or update RPC endpoints in `deployer`? Make sure the changes in `deployer` are deployed first before deploying any consumer (`receiver`, `hydro-consumer`, etc.) changes to avoid compatibility breaks.
- [ ] 📝 No `TODO` comments, or issues created to track follow up work
- [ ] ⚡️ Performance - What impact does this change have on performance? Is it slowing down or speeding up webhook processing?
- [ ] 🔬 Outer Loop Testing - What test coverage is there in `actions/canary`? If your change is
  risky or introducing some new feature, consider adding a new test workflow there. Additionally,
  you may also want to add test cases to `github/sauron` as well.


## Section Guidelines

### List the issues that this change affects.

Every code change must address _at least 1_ issue.
If an issue does not already exist, create one.

### What are you changing and why?

### What
This section should be used to describe your changes.
Consider including screenshots, videos, or graphs if they're applicable to your changes.

### Why

This is your opportunity to describe your thought process when making these changes.
You should:
1. List any tradeoffs you made to take on or pay down tech debt
1. Identify and work you did to mitigate risk
1. Describe any alternative approaches you considered and why you discarded them

### Anything you want to highlight for special attention from reviewers?

This is your chance to identify remaining risks and confess any uncertainties you may have about the correctness of the changes.
Highlight anything on which you would like a second (or third) opinion.
