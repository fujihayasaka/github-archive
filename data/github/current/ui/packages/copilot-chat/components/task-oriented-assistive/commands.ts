// eslint-disable-next-line import/no-namespace
import type * as icons from '@primer/octicons-react'

import {CopilotChatIntents, type CopilotChatIntentsType, type GeneratedSuggestion} from '../../utils/copilot-chat-types'

type CommandContext =
  | {context: 'global'}
  | {context: 'repository'}
  | {context: 'pull-request'; persona?: 'author' | 'reviewer' | 'other'}

export type Command = CommandContext & {
  type: 'task' | 'custom'
  intent?: CopilotChatIntentsType
  iconName: keyof typeof icons
  name: string
  prompt: string
}

const PULL_REQUEST_COMMANDS: Command[] = [
  {
    type: 'task',
    context: 'pull-request',
    persona: 'author',
    iconName: 'NoteIcon',
    name: 'Proof read this pull request',
    prompt: `Use the following info about this pull request:
- File changes
- Pull request description

And then provide answers to the following questions in separate paragraphs:
- A concise representation and reasoning of the file changes.
- Whether the pull request description reflects the purpose of the file changes. Please suggest possible improvements and present them with examples.
- Whether there is any complexities or notable efforts, such as handling edge cases or reducing technical debt.

Additional guidance:
- Provide a heading for each paragraph, formatted in bold.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
  },
  {
    type: 'task',
    context: 'pull-request',
    persona: 'reviewer',
    iconName: 'NoteIcon',
    name: 'Highlight focus areas for review in this pull request',
    prompt: `Use the following info about this pull request:
- File changes
- Pull request description
- Pull request reviews
- Pull request code comments
- Pull request issue comments

And then provide answers to the following questions in separate paragraphs:
- Provide insights on the scope and purpose of this pull request.
- Analyze the file changes and suggest risk areas that reviewers should focus on.
- Analyze the existing reviews and comments. Please highlight conversations that reviewers should pay attention to along with their links.

Additional Guidance:
- Provide a heading for each paragraph, formatted in bold.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
  },
  {
    type: 'task',
    context: 'pull-request',
    persona: 'other',
    iconName: 'NoteIcon',
    name: 'Explain this pull request',
    prompt: `Use the following info about this pull request:
- File changes
- Pull request description
- Pull request reviews
- Pull request code comments
- Pull request issue comments

And then provide answers to the following questions in separate paragraphs:
- Provide a high-level overview of the purpose of this pull request.
- Summarize the impact and potential risks for the file changes of this pull request.
- Provide a high-leverl overview on all coversations in this pull request.
- Indicate whether this pull request has been approved.

Additional Guidance:
- Provide a heading for each paragraph, formatted in bold.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
  },
  {
    type: 'task',
    context: 'pull-request',
    persona: 'author',
    iconName: 'NoteIcon',
    name: 'Catch me up on the reviews',
    prompt: `Use the following info about this pull request:
- Pull request description
- Pull request reviews
- Pull request code comments
- Pull request issue comments
- Pull request commits

Context:
- My latest commit refers to the most recent commit from me in this pull request.

1. First state my latest commit in this pull request use this format: "Your last commit was pushed at [timestamp]."
2. Ignore reviews and comments made earlier than the timestamp of my latest commit. Based on the remaining reviews and comments from other people in this pull request, provide answers to the following questions (use separate paragraphs with bold headings):
  - **Pull Request Status**: indicate if this pull request is approved or merged. If not merged, state whether anyone has reviewed or commented in this pull request after my latest commit.
  - **New Comments**: summarize the comments made by other people after my latest commit. Please highlight the ones that require further code changes or follow-ups.

Additional guidance:
- Output timestamp in a human-readable format.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
  },
  {
    type: 'task',
    context: 'pull-request',
    persona: 'reviewer',
    iconName: 'NoteIcon',
    name: 'Catch me up on the changes',
    prompt: `Use the following info about this pull request:
- File changes
- Pull request description
- Pull request reviews
- Pull request code comments
- Pull request issue comments
- Pull request commits

Context:
- My latest activity refers to the most recent review or comment from me in this pull request.

If I have not left any reviews or comments in this pull request:
1. First state that I have not reviewed this pull request.
2. Based on the commits, reviews, or comments in this pull request, provide answers to the following questions (use separate paragraphs with bold headings):
  - **Pull Request Status**: indicate if this pull request is approved or merged. If not merged, state whether anyone has reviewed or commented in this pull request.
  - **Code Changes**: Analyze the file changes and suggest risk areas that reviewers should focus on.
  - **Key Comments**: Analyze the existing reviews and comments. Please highlight conversations that reviewers should pay attention to along with their links.

If I have left reviews or comments in this pull request:
1. First state my latest activity in this pull request use this format: "Your last [review or comment] was posted at [timestamp]."
2. Ignore commits, reviews, and comments made earlier than the timestamp of my latest activity. Based on the remaining commits, reviews, and comments from other people in this pull request, provide answers to the following questions (use separate paragraphs with bold headings):
  - **Pull Request Status**: indicate if this pull request is approved or merged. If not merged, state whether anyone has committed, reviewed or commented in this pull request after my latest activity.
  - **New Code Changes**: summarize the new code changes from the commits made after my latest activity.
  - **New Comments**: summarize the new comments made by other people after my latest activity and highlight the ones I should pay attention to (with their links).

Additional guidance:
- Output timestamp in a human-readable format.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
  },
  {
    type: 'task',
    context: 'pull-request',
    persona: 'author',
    iconName: 'FileCodeIcon',
    name: 'Analyze build failures',
    prompt: `Use the following info about this pull request:
- File changes
- Pull request actions job logs

If all jobs passed successfully, stop there and report that there are no job errors.

Otherwise, provide answers to the following questions in separate paragraphs:
- Analyze the job failures with snippet of error logs. Please call out the type of failures (e.g. test failures, linting errors, compiler errors etc.).
- Suggest possible fixes for the job failures with examples. Please call out whether the failure is due to file changes from this pull request.

Additional guidance:
- Provide a heading for each paragraph, formatted in bold.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
    intent: CopilotChatIntents.actionsAgent,
  },
]

const REPOSITORY_COMMANDS: Command[] = [
  {
    type: 'task',
    context: 'repository',
    iconName: 'RepoIcon',
    name: 'Tell me about this repository',
    prompt: `Please provide answers to the following questions in separate paragraphs:
- Provide insights on the purpose of this repository. Please also provide a summary of its README if it exists.
- Provide detailed analysis on features and technologies used in this repository if it contains implementation of software system of any kind. Otherwise, provide an analysis on contents of this repository instead.

Additional guidance:
- Provide a heading for each paragraph, formatted in bold.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
  },
  {
    type: 'task',
    context: 'repository',
    iconName: 'RepoIcon',
    name: 'How to get started with this repository',
    prompt: `Please provide answers to the following questions in separate paragraphs:
- Provide the step by step snippet of installation and usage sections from this repository if they are mentioned in its README. Otherwise, skip this question.
- Provide summary of contribution guidelines of this repository to help new contributors to get started. Make sure to include links to related articles.
- Provide a link to issues good for new contributors.
- Provide list of contributors and maintainers for new contributors to reach out to.

Additional guidance:
- Provide a heading for each paragraph, formatted in bold.
- Do not output the paragrah in final response if the question is skipped or ignored.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
  },
  {
    type: 'task',
    context: 'repository',
    iconName: 'RepoIcon',
    name: 'Summarize activity for this repository in the last day',
    prompt: `Summarize all recent activity in this repository. "Recent activity" refers to the timeframe immediately preceding today's date. Use the GitHub global search API, filtered by 'repo:owner/repository' to return the following lists

- "Shipped" - PRs merged on or after yesterday's date
- "Pushed" - PRs pushed on or after yesterday's date, which are still open
- "Tracked" - Issues updated on or after yesterday's date

For each of these categories, produce a simple bulleted list, with a one-line description that includes the item number, along with the item title as a link. Each category header should include the total number of items, and a link to the complete results in the GitHub UI.`,
  },
]

const GLOBAL_COMMANDS: Command[] = [
  {
    type: 'task',
    context: 'global',
    iconName: 'GlobeIcon',
    name: 'Help me get started with Copilot',
    prompt: `What can I do with GitHub Copilot Chat Assistant in github.com? To help me get started, please provide prompt suggestions and their expected output.

Additional guidance:
- Provide a heading for each paragraph, formatted in bold.
- Keep your analysis succinct and conversational.
- Do not repeat or list the context details in your final response.
- Provide a concise synthesis of the information, avoiding unnecessary repetition.`,
  },
  {
    type: 'task',
    context: 'global',
    iconName: 'GlobeIcon',
    name: 'Summarize my activity in the last week',
    prompt: `Summarize my recent GitHub activity across all repositories. "Recent activity" refers to the timeframe immediately preceding today's date. Use the GitHub API to return the following lists

- "Pushed" - PRs created in the last 7 days, where I am the author, which are still open
- "Shipped" - PRs merged in the last 7 days, where I am the author
- "Tracked" - Issues created in the last 7 days, where I am the author
- "Contributed" - Issues where I have commented in the last 7 days
- "Reviewed" - PRs where I have commented or reviewed in the last 7 days

For each of these categories, produce a simple bulleted list, with a one-line description that includes the owner, repository, and item number in the format 'owner/repo#1234', along with the item title as a link. Each category header should include the total number of items, and a link to the complete results in the GitHub UI.`,
  },
]

export const COMMANDS: {[contextType: string]: Command[]} = {
  // eslint-disable-next-line prettier/prettier
  'pull-request': [
    ...PULL_REQUEST_COMMANDS,
    ...REPOSITORY_COMMANDS,
    ...GLOBAL_COMMANDS,
  ],
  // eslint-disable-next-line prettier/prettier
  'repository': [
    ...REPOSITORY_COMMANDS,
    ...GLOBAL_COMMANDS,
  ],
  // eslint-disable-next-line prettier/prettier
  'global': [
    ...GLOBAL_COMMANDS,
  ]
}

export function getCommandSuggestions(contextType?: string, persona?: string): GeneratedSuggestion[] {
  if (contextType === undefined) {
    return []
  }

  const commands = (COMMANDS[contextType] || [])
    .filter(command => command.context === contextType) // exclude parent contexts
    .filter(command => {
      if (persona === undefined) {
        return true
      }
      if (!('persona' in command)) {
        return true
      }
      if (command.persona === undefined) {
        return true
      }
      return command.persona === persona
    })

  return commands.map(command => ({
    question: command.name,
    prompt: command.prompt,
    intent: command.intent,
    mode: 'task-oriented-assistive',
  }))
}
