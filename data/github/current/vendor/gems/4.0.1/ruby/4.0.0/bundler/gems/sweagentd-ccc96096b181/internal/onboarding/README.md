# Onboarding

This directory contains the implementation of the "onboarding" Copilot Coding agent features.

- Onboarding tip -- This is a tip displayed at the bottom of the PR description with a link that, when clicked,
  fills in an onboarding issue template.

- Onboarding comment -- This is a PR comment added to the first ever Copilot Coding agent pull request a user
  makes for a particular repo, if no .github/copilot-instructions.md file or other instructions files are checked
  in.

## How it works
The feature is implemented entirely within sweagentd, with no runtime code. The strings in the markdown files
below are shipped by embedding them in sweagentd's binaries. When a job is started, the text is inserted as a
tip or comment respectively, doing string substitutions for the user's login, repo, and repo owner.

Clicking the link creates a new issue, assigned to Copilot, with a magic string that gets substituted for
the onboarding prompt before the job is run. This effectively helps conceal the prompt (though it may leak
in logs).

The prompt instructs Padawan to explore the repo and create instructions that tell how to setup the environment and build.

## Landmarks
- [onboarding_prompt.md](onboarding_prompt.md) - The prompt used to generate the instructions.
- [onboarding_tip.md](onboarding_tip.md) - The markdown added to the end of the PR description.
- [onboarding_comment.md](onboarding_comment.md) - The markdown added to the PR comment.

## Updating the prompt
When you update the prompt, be sure to regression test your changes by running an MSBench run.
You can do this from the Actions UI by checking the "Use repository instructions" checkbox.

Checking that box has the effect of causing the scenario to run 2X. The first run generates
the instructions, and the second evaluates their impact on the test scenario.

## Gotchas
- Be sure to check that the markdown link continues to work.
- The prompt is injected using a magic string, to avoid exceeding the max URI param length, and
  URI encoding issues with the embedded markdown.
- Be sure any changes to the URIs continue to assign Copilot to the issue.
- Take care when updating the prompt: repo instructions persist in user's repos, so if we do a
  poor job, we will silently degrade the experience without an easy way for us to push users
  to re-generate them again.
