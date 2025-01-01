import {generateText} from './ai'
import {getPrContext} from './get-pr-context'
import type {Template, PullRequest, HydratedIssueReference, DiffFile} from './types'

// Clean up
export type Classification = {
  name: string
  description: string
}

/* NEW */

const fileSummary = (file: DiffFile) => {
  return `### File:
${file.filePath} (${file.modificationType})

#### Hunks:
${file.hunks.map(hunk => `${hunk.hunkTitle}\n${hunk.rawUnifiedDiff}`).join('\n')}
_________
`
}

const filesChangedSummary = (files: DiffFile[]) => {
  return files.map(fileSummary).join('\n_________\n')
}

export async function generateGroupDescription({
  apiUrl,
  groupTitle, // title of the group
  extractedIssues, // issues extracted from the pull request title/description
  pullRequest, // the pull request
  filesChanged, // the files changed in this group
  template, // the template for the group
}: {
  apiUrl: string
  groupTitle: string
  extractedIssues: HydratedIssueReference[]
  pullRequest: PullRequest
  filesChanged: DiffFile[]
  template: Template
}) {
  const system = `You are an AI agent that helps code reviewers understand code changes in a pull request Your task is to summarize a subset of the changes in a pull request.
Instructions:
- **Avoid** starting your response with "This group contains..." or "This pull request includes...".
- **Use the reviewer instructions** and issues to inform your groupings and priorities.
- **Do not mislead** or misrepresent.
- **Use related issues** to inform your description. It's really helpful to highlight the relationship between the code changes and the issues when possible.
- **Avoid sensationalizing changes**. Do not say things like "this change is crucial" or "this is a major change". Just state observable facts.
- **Only use Markdown** for:
  - Inline code style for short tokens, e.g. \`Button.tsx\`.
  - Referencing GitHub issues, e.g. #123 => [#123](https://github.com/${pullRequest.base.repo.owner.login}/${pullRequest.base.repo.name}/issues/123)
- **Do not use markdown** for:
  - Adding headings or subheadings

Reviewer Instructions:
${template.instructions}`

  const prompt = `Summarize the following group of related changes in a pull request:

${getPrContext(pullRequest, [], extractedIssues)}

---
## Files Changed in This Group
Group Title: ${groupTitle}

${filesChangedSummary(filesChanged)}`

  const text = await generateText(apiUrl, 'gpt-4o', prompt, system, 0.2)

  return text
}
