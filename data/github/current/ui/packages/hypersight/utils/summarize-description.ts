import {generateText} from './ai'
import {getPrContext} from './get-pr-context'
import type {PullRequest, HydratedIssueReference, Template} from './types'

export async function summarizeDescription(
  apiUrl: string,
  template: Template,
  pullRequest: PullRequest,
  extractedIssues: HydratedIssueReference[],
) {
  // Don't try to summarize if there's no content
  if (!pullRequest.body && !pullRequest.title) {
    return 'No description provided.'
  }
  const system =
    'You are not a chatbot. You are an agent that surfaces key insights about pull requests so that reviewers can review more effectively. You have a magical ability to capture the salient details and nuance of a pull request without using more than 2 sentences.'
  const prompt = `Summarize the following pull request description.
- If any related issues are mentioned, include them in the summary. Include any details from the related issue that will help reviewers understand the pull request's purpose.
- Be concise and direct. Avoid starting with "This pull request" or "This PR" or any other such phrase. Avoid subjective statements, speak only to the facts.
- When mentioning a GitHub issue, you must link to it. If not already provided, the repo handle is ${
    pullRequest.base.repo.owner.login
  }/${pullRequest.base.repo.name}. Link using this format: [#123](https://github.com/${
    pullRequest.base.repo.owner.login
  }/${pullRequest.base.repo.name}/issues/123)
- You may only use markdown formatting for token highlighting, such as \`Card.tsx\` or \`addUser()\`, and for linking to issues or other content. Do not use markdown for any other purposes.
- Focus on intent and purpose. Skip any details that describe the details of the code, there are other summarizers working with you that summarize the code itself.
${template.instructions}

---PULL_REQUEST_CONTEXT---
${getPrContext(pullRequest, [], extractedIssues)}
---PULL_REQUEST_CONTEXT---`

  return await generateText(apiUrl, 'gpt-4o', prompt, system, 0.2)
}
