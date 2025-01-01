import {streamText} from './ai'
import {getPrContext} from './get-pr-context'
import type {DiffHunk, HydratedIssueReference, PullRequest, Template, ExplanationDepth} from './types'

function gameLogicExplanation(depth: ExplanationDepth): string {
  switch (depth) {
    case 'None':
      return ''
    case 'Light':
      return 'Core game mechanics implementation.'
    case 'Balanced':
      return 'Implements core game mechanics including piece movement and collision detection.'
    case 'Moderate':
      return 'Implements the core game mechanics including piece movement, collision detection, and game state management. The changes focus on creating a robust foundation for the game logic.'
    case 'Full':
      return 'This section implements the fundamental game mechanics that drive the Tetris gameplay experience. The changes include:\n- Piece movement logic: Controls how tetrominoes move and rotate\n- Collision detection: Ensures pieces interact correctly with walls and other pieces\n- Game state management: Tracks the current game state, score, and level progression\n\nThe implementation follows standard game development patterns, using a game loop to handle updates and render cycles.'
  }
}

function shapeDefinitionExplanation(depth: ExplanationDepth): string {
  switch (depth) {
    case 'None':
      return ''
    case 'Light':
      return 'Tetromino shape definitions.'
    case 'Balanced':
      return 'Defines the standard Tetris piece shapes and their rotation states.'
    case 'Moderate':
      return 'Defines the seven standard Tetris piece shapes (tetrominoes) and their possible rotation states. Each shape is represented using a matrix that can be transformed for rotation.'
    case 'Full':
      return 'This section defines the fundamental building blocks of Tetris - the tetromino shapes. Key aspects include:\n- Shape matrices: Each of the seven standard Tetris pieces (I, O, T, S, Z, J, L) is defined using a 2D matrix\n- Rotation states: All possible rotations for each shape are pre-calculated\n- Color definitions: Each piece type has an associated color for visual distinction\n\nThe implementation uses standard matrix notation for shape definitions, making it easy to perform transformations and collision checks.'
  }
}

const depthInstructions: Record<ExplanationDepth, string> = {
  None: 'You must provide a walkthrough that ONLY includes diff hunks and h2 or h3 section titles with no additional explanatory text. Do not include any other text in the walkthrough.',
  Light:
    'You must provide a walkthrough that provides extremely brief explanations and instead focuses prioritizes showing diff hunks rather than explanatory text. Text should be used to highlight important changes, risks, or sections that address the related issues.',
  Balanced:
    'You must provide a walkthrough that balances both diff hunks and explanatory text. Explain all of the important changes, but avoid being verbose. Provide a brief explanation of how each section addresses any relevant issues that have been provided.',
  Moderate:
    'You must provide a walkthrough that provides a high-level explanation of changes using primarily text. Reference diff hunks when necessary. Provide an in-depth explanation of how each section addresses any relevant issues that have been provided.',
  Full: 'You must provide a walkthrough that provides a detailed explanation of changes using text only--no diff hunks should be referenced. Provide a full explanation of the changes, including the intent of the changes and how they address any related issues. Include a brief definition of any technical terms used in each walkthrough section.',
}

export async function generateMarkdownWalkthrough({
  apiUrl,
  streamCallback,
  pullRequest,
  mentionedIssues,
  diffHunks,
  template,
  depth,
  preferences,
}: {
  apiUrl: string
  pullRequest: PullRequest
  mentionedIssues: HydratedIssueReference[]
  diffHunks: DiffHunk[]
  streamCallback: (chunk: string) => void
  template: Template
  depth: ExplanationDepth
  preferences: string
}): Promise<void> {
  const system = `You are an AI assistant that helps code reviewers understand proposed changes from a pull request by organizing the details of the pull request into a helpful walkthrough.

Before beginning your walkthrough, you should first provide the reviewer with a high level "Overview" of the pull request. This should be a single paragraph that captures the intent of the changes. Below are specific instructions for the overview section.

## Instructions for generating the overview section

- The overview section should summarize the intent and purpose of the pull request as concisely as possible.
- Always begin the overview section with an H2 header titled "Overview".
- If any related issues are provided below, then include them in the summary. Include any details from the related issue that will help reviewers understand the pull request's purpose. Help the user understand how the changes in the pull request relate to the issues.
- Be concise and direct. Avoid starting with "This pull request" or "This PR" or any other such phrase. Avoid subjective statements, speak only to the facts.
- Do not restate the PR title or description in your output.
- When referencing a GitHub issue, you must link to it. If not already provided, the repo handle is ${
    pullRequest.base.repo.owner.login
  }/${pullRequest.base.repo.name}. Link using this format: [#123](https://github.com/${
    pullRequest.base.repo.owner.login
  }/${pullRequest.base.repo.name}/issues/123)
- In this section, you may only use markdown formatting for inline code highlighting, such as \`Card.tsx\` or \`addUser()\`, and for linking to issues or other content. Do not use markdown for any other purposes.
- Focus on intent and purpose. Skip any details that describe the details of the code as this will be included in the walkthrough sections below.


## Walkthrough instructions

After the overview section, you will provide a detailed walkthrough of the changes in the pull request. This should be organized into sections that are easy to read and understand. Below are specific instructions for generating the walkthrough.

- Your goal is to help reviewers understand the big picture as quickly as possible. As such, it's critical that you lead with the changes that are most reflective of the PRs intent. first.
- Unless stated otherwise by the reviewer, secondary changes, such as cosmetic changes, auto-generated files, and other non-critical changes should be mentioned at the end of the walkthrough (or not at all).
- Do not cite any code directly in your output. Instead, use hunk references to present code to the user. Reviewers still need to see a lot of code, so be sure you are citing relevant hunks for the reviewer to see.
- Avoid sensationalizing or editorializing changes. Do not say things like "massive" or "crucial" changes. Just state the facts.
- Avoid mentioning the word "hunk" in your output. Just talk about the intent of the changes and reference the hunk directly (see instructions below).
- Each section of the walkthrough should consist of a title (h2), a description (p), and a list of changes (hunk references i.e. [HUNK: hunkId1] [HUNK: hunkId2]). If the section is related to a mentioned issue, then describe how the section resolves the issue. Provide a link to the issue.
- Before rendering the walkthrough, you may render a summary or preamble if the user has requested information about the PR that does not fit within the walkthrough format.
- Do NOT render lists (ul) or list items (li) in your output.
- Output valid Markdown only, no JSON.
- Do not lead with phrases like "The purpose of this pull request", "The primary objective of this pull request", or "this pull request". The user knows they are viewing a pull request, they don't need you to tell them that. Get to the details as quickly as possible. i.e. "This implements a new component and resolves #123 by xyz..."
- A list of "hunkSummaries", where each has a unique "hunkId". You must reference these IDs exactly in your final output. Do not invent or alter them.

## Rendering sections of your walkthrough

Your walkthrough should be comprised of sections. Each section shall contain a title (h2) and a list of sub-sections presented as an h3 title, paragraph description, and list of diff hunks. It's critical that you follow this format.

${depthInstructions[depth]}

Example response:

## Tetris Game implementation

### Game logic

${gameLogicExplanation(depth)}

\`\`\`diff:lib/utils/game.ts
[HUNK:2]
\`\`\`

\`\`\`diff:app/App.tsx
[HUNK:4]
\`\`\`

### Shape definitions

${shapeDefinitionExplanation(depth)}

\`\`\`diff:lib/utils/shapes.ts
[HUNK:1]
[HUNK:3]
\`\`\`

## Rules for using markdown in the walkthrough

It's absolutely CRITICAL that you use markown according to the following requirements. Failure to do so will result in the UI not rendering your output correctly.

- Only the following markdown elements are permitted. Anything else is strictly forbidden:
  - Inline code style for short tokens, e.g. \`Button.tsx\`.
  - Code blocks for mentioning diff hunks, i.e. \`\`\`diff:file.ts\n[HUNK:1]\`\`\`.
  - Links to GitHub issues, i.e. #123 => [#123](https://github.com/owner/repo/issues/123)
  - Rendering section titles (h2, h3) or section text (p)
- Under no circumstances should you use the following markdown elements:
  - Lists (ul)
  - List items (li)
  - Headings (h1, h4, h5, h6)

## Referencing hunks and files

Our UI layer will automatically replace hunk references with the actual diff lines. You must follow the following instructions when referencing hunks:
- Reference hunks using a block (triple backtick) code element. Do not include any other text within the code block.
- You may reference multiple hunks in a single block, i.e. \`[HUNK: hunkId1] [HUNK: hunkId1]\`
- You must specify the hunk's file path in the code block language attribute using the "diff:" prefix,  i.e. diff:path/to/file.tsx
- Only use hunk IDs or file paths that have been provided to you. Never make up your own references.`

  // Prompt with instructions and context
  const prompt = `Please analyze the following pull request and diff hunks.
${getPrContext(pullRequest, diffHunks, mentionedIssues)}

## Reviewer Instructions
${template.instructions}

Remember, your output must be valid markdown. No other commentary.

  ${preferences ? `\nPreferences: ${preferences}` : ''}
  `
  return streamText(apiUrl, 'gpt-4o', prompt, streamCallback, system)
}
