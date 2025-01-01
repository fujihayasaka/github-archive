import type {DashboardIssue} from '../types'

type CopilotMessage = {
  role: string
  content: string
}

export function buildMessages(issues: DashboardIssue[], prompt: string): CopilotMessage[] {
  return [buildSystemMessage(prompt), ...buildUserMessages(issues)]
}

function buildSystemMessage(prompt: string): CopilotMessage {
  return {
    role: 'system',
    content: prompt.concat(
      '\nReturn a JSON object with the issue titles as keys and the one-sentence summary as a value.',
    ),
  }
}

function buildUserMessages(issues: DashboardIssue[]): CopilotMessage[] {
  return issues.map(issue => {
    const commentContent = issue.comments
      .map(comment => {
        return `${comment.author} commented: ${comment.body}`
      })
      .join('\n')

    const content = `Title: ${issue.title}\n Description: ${issue.description}\n Comments: ${commentContent}`
    return {
      role: 'user',
      content,
    }
  })
}
