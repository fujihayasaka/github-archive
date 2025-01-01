export const issuesData = `
data:
- url: "https://github.com/primer/react/issues/5753"
  state: "open"
  draft: false
  title: "Release Tracking"
  number: 5753
  created_at: "2025-03-10T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels: []
  author: "github-actions[bot]"
  comments: 0
  assignees_avatar_urls:
  - "https://avatars.githubusercontent.com/in/15368?v=4"
- url: "https://github.com/primer/react/issues/4694"
  state: "open"
  draft: false
  title: "<AnchoredOverlay> needs to be upgraded to popover"
  number: 4694
  created_at: "2024-06-24T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels:
  - "bug"
  - "size: pebble"
  - "Stale"
  - "react"
  - "component: AnchoredOverlay"
  author: "keithamus"
  comments: 4
  assignees_avatar_urls: []
- url: "https://github.com/primer/react/issues/5732"
  state: "closed"
  draft: false
  title: "Release Tracking"
  number: 5732
  created_at: "2025-03-03T00:00:00Z"
  closed_at: "2025-03-10T00:00:00Z"
  merged_at: ""
  labels: []
  author: "github-actions[bot]"
  comments: 1
  assignees_avatar_urls:
  - "https://avatars.githubusercontent.com/in/15368?v=4"
- url: "https://github.com/primer/react/issues/5672"
  state: "open"
  draft: false
  title: "Checked radio does not display properly"
  number: 5672
  created_at: "2025-02-08T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels:
  - "bug"
  - "react"
  author: "swiing"
  comments: 3
  assignees_avatar_urls:
  - "https://avatars.githubusercontent.com/u/26746305?v=4"
- url: "https://github.com/primer/react/issues/3721"
  state: "open"
  draft: false
  title: "Portal is not ssr compat - accesses \`document\` during render"
  number: 3721
  created_at: "2023-09-08T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels:
  - "bug"
  - "react"
  author: "mattcosta7"
  comments: 10
  assignees_avatar_urls: []
`

export const pullsData = `
data:
- type: 'pr'
  url: 'https://github.com/github/repo/pull/1'
  state: 'open'
  draft: false
  created_at: '2023-01-01T00:00:00Z'
  closed_at: null
  merged_at: null
  title: 'First pull request'
  number: 1
  labels: ['bug', 'help wanted']
  author: 'octocat'
  comments: 5
  assignees_avatar_urls: ['https://github.com/octocat.png']

- type: 'pr'
  url: 'https://github.com/github/repo/pull/2'
  state: 'closed'
  draft: false
  created_at: '2023-01-02T00:00:00Z'
  closed_at: '2023-01-03T00:00:00Z'
  merged_at: '2023-01-03T00:00:00Z'
  title: 'Second pull request'
  number: 2
  labels: ['enhancement']
  author: 'hubot'
  comments: 2
  assignees_avatar_urls: ['https://github.com/hubot.png']

- type: 'pr'
  url: 'https://github.com/github/repo/pull/3'
  state: 'open'
  draft: true
  created_at: '2023-01-03T00:00:00Z'
  closed_at: null
  merged_at: null
  title: 'Third pull request'
  number: 3
  labels: ['question']
  author: 'octocat'
  comments: 0
  assignees_avatar_urls: []

- type: 'pr'
  url: 'https://github.com/github/repo/pull/4'
  state: 'open'
  draft: false
  created_at: '2023-01-04T00:00:00Z'
  closed_at: null
  merged_at: null
  title: 'Fourth pull request'
  number: 4
  labels: ['documentation']
  author: 'hubot'
  comments: 1
  assignees_avatar_urls: ['https://github.com/hubot.png']
`

export const partialIssueData = `
data:
- url: "https://github.com/primer/react/issues/1234"
  state: "open"
  title: "Missing author field"
  number: 1234
  created_at: "2025-04-01T00:00:00Z"
  labels: []
  comments: 0
  assignees_avatar_urls: []

- url: "https://github.com/primer/react/issues/5678"
  state: "closed"
  title: "Missing labels and assignees"
  number: 5678
  created_at: "2025-04-02T00:00:00Z"
  closed_at: "2025-04-03T00:00:00Z"
  comments: 2

- url: "https://github.com/primer/react/issues/9101"
  title: "Missing comments and state"
  number: 9101
  created_at: "2025-04-04T00:00:00Z"
  labels: ["enhancement"]
  author: "octocat"
  assignees_avatar_urls: ["https://avatars.githubusercontent.com/u/583231?v=4"]

- url: "https://github.com/primer/react/issues/1121"
  title: "Missing created_at and number"
  state: "open"
  labels: ["bug"]
  author: "hubot"
  comments: 3
  assignees_avatar_urls: []

- url: "https://github.com/primer/react/issues/3141"
  state: "open"
  number: 3141
  created_at: "2025-04-05T00:00:00Z"
  labels: []
  author: "github-actions[bot]"
  comments: 1
  assignees_avatar_urls: []

- url: "https://github.com/primer/react/issues/3145"
  state: "open"
  created_at: "2025-04-05T00:00:00Z"
  labels: []
  author: "github-actions[bot]"
  comments: 1
  assignees_avatar_urls: []

- url: "https://github.com/primer/react/issues/1256"
  title: "Missing author, date, and state"
  number: 1236
  labels: []
  comments: 0
  assignees_avatar_urls: []
`
