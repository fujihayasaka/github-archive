export const copilotChatTextAreaId = 'copilot-chat-textarea'
export const copilotChatSearchInputId = 'copilot-chat-topic-search'
export const reviewUserMessage = 'Review'
export const copilotChatHeaderButtonID = 'copilot-chat-header-button'

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

export const threadSuggestions: Record<string, string[]> = {
  repository: [
    'What questions can I ask?',
    'What does this repository do?',
    'How should I get started exploring this repo?',
    'Can you tell me about this repository?',
  ],
  issue: [
    'Summarize this issue.',
    'What are the main points being discussed here?',
    'Suggest next steps for this issue.',
  ],
  alert: ['Summarize this alert.'],
  file: ['Explain this file.', 'Summarize this file for me.', 'How can I improve this file?'],
  'pull-request': [
    'Summarize this pull request.',
    'What commits are included in this PR?',
    'Can you tell me more about this commit?',
  ],
  discussion: [
    'Summarize this discussion.',
    'Summarize the comments made by user in a discussion.',
    'What were some key decisions made in this discussion?',
  ],
  job: ['Why did this job fail?', 'How can I fix this build?'],
  default: [
    'What questions can I ask?',
    'What is the best way to get started with Copilot?',
    'How do I clone this repository?',
    'How do I revert a commit?',
    'How do I add myself as a reviewer?',
    'How do I create a repository?',
  ],
}
