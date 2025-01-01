import {CopilotChatIntents, type GeneratedSuggestion} from './copilot-chat-types'

export function getFailedActionsJobPrompt(jobId?: number) {
  const jobContext = jobId != null ? `failing job ${jobId}` : 'this failing job'
  return `Please find a solution for ${jobContext}. Use the logs, job definition, and any referenced files where the failure occurred. Keep your response focused on the solution and include code suggestions when appropriate.`
}

export const suggestedPrompts: Record<string, string[]> = {
  'Languages & frameworks': [
    'Show me Python beginner projects.',
    "Explain Java's garbage collection.",
    'Start me off with Node.js.',
    'Introduce me to Django best practices.',
  ],
  'Tools & environments': [
    'Set up a local development environment.',
    'Demonstrate the basics of Docker.',
    'Get me started with Git.',
    'Recommend popular VS Code extensions.',
  ],
  'Open source & contribution': [
    'Suggest 10 open source projects I can contribute to.',
    'Walk me through the GitHub Pull Request flow.',
    'How do I start my own open source project?',
    "Guide me through contributing to React's codebase.",
  ],
  'Best practices & concepts': [
    'Explain the SOLID principles of object-oriented design.',
    'Introduce me to test-driven development.',
    'Describe common design patterns.',
    'Teach me about RESTful API design.',
  ],
  'Web development': [
    'Guide me through creating a basic website.',
    'Introduce HTML5 and CSS3 features.',
    'Explain responsive web design.',
    'Start me off with Tailwind CSS.',
  ],
  'Databases & data': [
    'Get me started with SQL queries.',
    'Recommend popular NoSQL databases.',
    'How to back up a database?',
    'Give a walkthrough on normalizing a database.',
  ],
  'Algorithms & data structures': [
    'Teach me basic sorting algorithms.',
    'Explain binary search trees.',
    'Introduce me to graph algorithms.',
    'What is a hash table?',
  ],
  'Security & authentication': [
    'Give a guide on basic web security.',
    'Show me how to set up OAuth.',
    "What's a JSON Web Token?",
    'Describe common encryption techniques.',
  ],
  'Mobile development': [
    'Kickstart my journey with Android development.',
    'Introduce me to iOS app basics.',
    'Recommend cross-platform mobile frameworks.',
    'Give a guide to the app store submission process.',
  ],
  'Cloud & DevOps': [
    'Start me off with AWS basics.',
    'How do I deploy apps on Azure DevOps?',
    'Introduce me to Kubernetes.',
    'What are the basics of continuous integration/continuous deployment?',
  ],
  'Frontend frameworks & libraries': [
    'Get me started with React.',
    'Walk me through Vue.js essentials.',
    'What are some best practices in Angular development?',
    'How do I use Svelte for web apps?',
  ],
  'Performance & optimization': [
    'Teach me about website performance optimization.',
    'Explain database indexing benefits.',
    'What are some tips to optimize JavaScript code?',
    'Give a guide to efficient API caching.',
  ],
}

export const threadSuggestions: Record<string, GeneratedSuggestion[]> = {
  repository: [
    {question: 'What questions can I ask?'},
    {question: 'What does this repository do?'},
    {question: 'How should I get started exploring this repo?'},
    {question: 'Can you tell me about this repository?'},
  ],
  issue: [
    {question: 'Summarize this issue.'},
    {question: 'What are the main points being discussed here?'},
    {question: 'Suggest next steps for this issue.'},
  ],
  alert: [{question: 'Summarize this alert.'}],
  file: [
    {question: 'Explain this file.'},
    {question: 'Summarize this file for me.'},
    {question: 'How can I improve this file?'},
  ],
  'pull-request': [
    {question: 'Summarize this pull request.'},
    {question: 'What commits are included in this PR?'},
    {question: 'Can you tell me about the changes in this PR?'},
  ],
  discussion: [
    {question: 'Summarize this discussion.'},
    {question: 'Summarize the comments made by user in a discussion.'},
    {question: 'What were some key decisions made in this discussion?'},
  ],
  job: [
    {
      question: 'Why did this job fail?',
      intent: CopilotChatIntents.actionsAgent,
    },
    {
      question: 'How can I fix this build?',
      intent: CopilotChatIntents.actionsAgent,
    },
  ],
  default: [
    {question: 'What questions can I ask?'},
    {question: 'What is the best way to get started with Copilot?'},
    {question: 'How do I clone this repository?'},
    {question: 'How do I revert a commit?'},
    {question: 'How do I add myself as a reviewer?'},
    {question: 'How do I create a repository?'},
  ],
  issues: [
    {question: 'How do I create an issue?'},
    {question: 'How do I filter issues by label?'},
    {question: 'What are the most recently updated issues?'},
  ],
  'pull-requests': [
    {question: 'How do I create a pull request?'},
    {question: 'How do I filter pull requests by label?'},
    {question: 'How do I reopen a closed pull request?'},
  ],
  discussions: [
    {question: 'How do I start a new discussion?'},
    {question: 'How do I filter discussions by category or tag?'},
    {question: 'How do I search for a specific discussion?'},
  ],
}
