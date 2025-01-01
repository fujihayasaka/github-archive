export function getDefaultIssueSummaryPrompt(userDisplayLogin: string) {
  return `
  The following are GitHub issues with titles, descriptions, and comments.
  For each issue:
  - Write a brief, one-sentence summary for @${userDisplayLogin}.
  - The summary should tell @${userDisplayLogin} if there's any action they need to take.
  - The summary should help @${userDisplayLogin} understand the current state of the issue.
  - @-mention OTHER users if they are making a request (for example, "@user requests that you...").
  DO NOT @-mention @${userDisplayLogin}. Refer to them as 'you' instead.
  `
}
