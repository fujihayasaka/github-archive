import {generateText} from './ai'
import type {DiffHunk, HydratedIssueReference, PullRequest} from '../utils/types'
export async function generateSuggestedQuestions(
  apiUrl: string,
  pullRequest: PullRequest,
  extractedIssues: HydratedIssueReference[],
  diffs: DiffHunk[],
) {
  try {
    // Don't try to generate questions if there's no content
    if (!pullRequest.body && !pullRequest.title) {
      return ['What is the purpose of this pull request?']
    }

    const system =
      'You are an AI assistant that helps code reviewers by generating insightful questions about pull requests. These questions should lead the reviewer towards a deeper understanding of the impacts and potential issues of the pull request. It is critical that you lead the reviewer towards a better understanding through the questions you create. A separate agent will answer these questions if the reviewer chooses to ask them. That Agent has access to the entire code base through a powerful agentic search. Use this to your advantage and generate questions that are likely to be answered by the Agent resulting in compelling insights that would otherwise be difficult for the reviewer to discover.'

    const prompt = `Generate 5 specific questions that a reviewer might have about this pull request.
  **Instructions**:
- Great questions will lead to interesting insights when answered by the answer agent. You must Generate questions that lead the reviewer to a "Conceptual Diff"--meaning the reviewer learns more about the current state of the system and its behaviors through the search agent's answer to the question you generate.
- Focus on questions that are specific to the details of this pull request.
- Questions should help the reviewer understand the impact, intention, design decisions, and potential issues.
- Questions should be concise and direct. Do not exceed 15 words.
- Do not ask overly generic questions like "What is the purpose of this PR?" unless the PR lacks a clear description.

---PULL_REQUEST_CONTEXT---
Title:
${pullRequest.title} (#${pullRequest.number})
---
Body:
${pullRequest.body}
${
  extractedIssues.length > 0
    ? `---
Related issues:
${extractedIssues.map(issue => `${issue.title} #${issue.issueNumber}\n${issue.body}\n`).join('\n')}`
    : ''
}
---
Changes in this pull request:
${diffs}`

    const text = await generateText(apiUrl, 'gpt-4o', prompt, system, 0.2)

    if (!text) {
      throw new Error('No questions generated')
    }

    // Parse the response into an array of questions
    const questions = text
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.endsWith('?'))
      .map(line => line.replace(/^\d+\.\s*/, '')) // Remove any leading numbers

    return questions.length > 0 ? questions : ['What is the purpose of this pull request?']
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error in generateSuggestedQuestions:', error)
    return ['What is the purpose of this pull request?']
  }
}
