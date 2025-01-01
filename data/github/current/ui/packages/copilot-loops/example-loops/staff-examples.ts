import type {Pipeline} from '../types/app'

export type ExampleLoop = {
  altText: string
  loop: Pick<Pipeline, 'title' | 'description' | 'nodes'>
  assetPath: string
}

export const battleRoyaleExample: ExampleLoop = {
  altText: 'GitHub Battle Royale report',
  assetPath: '/images/modules/loops/BattleRoyal.png',
  loop: {
    title: 'GitHub Battle Royale',
    description: 'Compare two GitHub users based on their pull request contributions and metrics',
    nodes: [
      {
        id: '1',
        type: 'text',
        title: 'Start Date',
        description: 'The date 6 months ago from which to fetch data',
        content: '2024-11-06',
        inputType: {
          type: 'text',
        },
      },
      {
        id: '5',
        type: 'text',
        title: 'First Username',
        description: 'GitHub username for the first contestant',
        content: 'jonrohan',
        inputType: {
          type: 'text',
        },
      },
      {
        id: '6',
        type: 'text',
        title: 'Second Username',
        description: 'GitHub username for the second contestant',
        content: 'colebemis',
        inputType: {
          type: 'text',
        },
      },
      {
        id: '7',
        type: 'text',
        title: 'Repository',
        description: 'The repository to analyze (in owner/name format)',
        content: 'primer/react',
        inputType: {
          type: 'text',
        },
      },
      {
        id: '2',
        type: 'github-graphql',
        title: 'First User PRs',
        description: 'Fetch PRs for the first user',
        content:
          'query {\n  search(query: "repo:{{7}} author:{{5}} is:pr created:>={{1}}", type: ISSUE, first: 100) {\n    edges {\n      node {\n        ... on PullRequest {\n          title\n          merged\n          closed\n          createdAt\n          mergedAt\n          additions\n          deletions\n          commits {\n            totalCount\n          }\n          repository {\n            nameWithOwner\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '3',
        type: 'github-graphql',
        title: 'Second User PRs',
        description: 'Fetch PRs for the second user',
        content:
          'query {\n  search(query: "repo:{{7}} author:{{6}} is:pr created:>={{1}}", type: ISSUE, first: 100) {\n    edges {\n      node {\n        ... on PullRequest {\n          title\n          merged\n          closed\n          createdAt\n          mergedAt\n          additions\n          deletions\n          commits {\n            totalCount\n          }\n          repository {\n            nameWithOwner\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '4',
        type: 'prompt',
        title: 'Battle Analysis',
        description: 'Compare the two users and determine a winner',
        content:
          "You're a GitHub Battle Royale announcer. Compare the following metrics between these two contestants based on their pull request data:\n\n# Battle Royal 🤴🗡️👸\n\n1. Total PRs created\n2. PR merge rate\n3. Lines of code changed (additions + deletions)\n4. Average commits per PR\n5. PR velocity (PRs per month)\n\nUser 1 ({{5}}) data: {{2}}\nUser 2 ({{6}}) data: {{3}}\n\nAnalyze each metric and assign points (1-10) for each category. Then declare an overall winner with a dramatic announcement. Format your response as an exciting battle commentary.",
      },
    ],
  },
}

const githubGossipExample: ExampleLoop = {
  altText: 'GitHub repo feature announcement magazine',
  assetPath: '/images/modules/loops/NewsFlash.png',
  loop: {
    title: 'Multi-Repo GitHub Feature Announcement Magazine',
    description:
      'Creates a tabloid-style frontpage focusing on new features and enhancements across multiple GitHub repositories',
    nodes: [
      {
        id: 'repo1',
        type: 'text',
        title: 'Repository 1',
        description: 'First repository to analyze (format: owner/repo)',
        content: 'facebook/react',
        inputType: {
          type: 'text',
        },
      },
      {
        id: 'repo2',
        type: 'text',
        title: 'Repository 2',
        description: 'Second repository to analyze (format: owner/repo)',
        content: 'microsoft/vscode',
        inputType: {
          type: 'text',
        },
      },
      {
        id: 'repo3',
        type: 'text',
        title: 'Repository 3',
        description: 'Third repository to analyze (format: owner/repo)',
        content: 'primer/react',
        inputType: {
          type: 'text',
        },
      },
      {
        id: 'days',
        type: 'text',
        title: 'Days Limit',
        description: 'Number of days to look back for data',
        content: '30',
        inputType: {
          type: 'text',
        },
      },
      {
        id: 'date_limit',
        type: 'prompt',
        title: 'Calculate Date Limit',
        description: 'Calculate the date limit based on the number of days',
        content: 'Calculate the date {{days}} days ago from today in YYYY-MM-DD format.',
      },
      {
        id: '3',
        type: 'github-graphql',
        title: 'Feature PRs - Repository 1',
        description: 'Fetch recent feature/enhancement pull requests from the first repository',
        content:
          'query {\n  search(query: "repo:{{repo1}} is:pr created:>={{date_limit}} sort:updated-desc", type: ISSUE, first: 10) {\n    edges {\n      node {\n        ... on PullRequest {\n          title\n          url\n          author {\n            login\n          }\n          createdAt\n          additions\n          deletions\n          changedFiles\n          body\n          labels(first: 5) {\n            edges {\n              node {\n                name\n              }\n            }\n          }\n          reviews(first: 3) {\n            nodes {\n              author {\n                login\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '4',
        type: 'github-graphql',
        title: 'Feature PRs - Repository 2',
        description: 'Fetch recent feature/enhancement pull requests from the second repository',
        content:
          'query {\n  search(query: "repo:{{repo2}} is:pr created:>={{date_limit}} sort:updated-desc", type: ISSUE, first: 10) {\n    edges {\n      node {\n        ... on PullRequest {\n          title\n          url\n          author {\n            login\n          }\n          createdAt\n          additions\n          deletions\n          changedFiles\n          body\n          labels(first: 5) {\n            edges {\n              node {\n                name\n              }\n            }\n          }\n          reviews(first: 3) {\n            nodes {\n              author {\n                login\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '5',
        type: 'github-graphql',
        title: 'Feature PRs - Repository 3',
        description: 'Fetch recent feature/enhancement pull requests from the third repository',
        content:
          'query {\n  search(query: "repo:{{repo3}} is:pr created:>={{date_limit}} sort:updated-desc", type: ISSUE, first: 10) {\n    edges {\n      node {\n        ... on PullRequest {\n          title\n          url\n          author {\n            login\n          }\n          createdAt\n          additions\n          deletions\n          changedFiles\n          body\n          labels(first: 5) {\n            edges {\n              node {\n                name\n              }\n            }\n          }\n          reviews(first: 3) {\n            nodes {\n              author {\n                login\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '6',
        type: 'github-graphql',
        title: 'Feature Requests - Repository 1',
        description: 'Fetch recent feature request issues from the first repository',
        content:
          'query {\n  search(query: "repo:{{repo1}} is:issue label:\\"Type: Feature Request\\" created:>={{date_limit}} sort:updated-desc", type: ISSUE, first: 10) {\n    edges {\n      node {\n        ... on Issue {\n          title\n          url\n          author {\n            login\n          }\n          createdAt\n          body\n          labels(first: 5) {\n            edges {\n              node {\n                name\n              }\n            }\n          }\n          comments {\n            totalCount\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '7',
        type: 'github-graphql',
        title: 'Feature Requests - Repository 2',
        description: 'Fetch recent feature request issues from the second repository',
        content:
          'query {\n  search(query: "repo:{{repo2}} is:issue label:enhancement,feature-request created:>={{date_limit}} sort:updated-desc", type: ISSUE, first: 10) {\n    edges {\n      node {\n        ... on Issue {\n          title\n          url\n          author {\n            login\n          }\n          createdAt\n          body\n          labels(first: 5) {\n            edges {\n              node {\n                name\n              }\n            }\n          }\n          comments {\n            totalCount\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '8',
        type: 'github-graphql',
        title: 'Feature Requests - Repository 3',
        description: 'Fetch recent feature request issues from the third repository',
        content:
          'query {\n  search(query: "repo:{{repo3}} is:issue label:enhancement,feature-request created:>={{date_limit}} sort:updated-desc", type: ISSUE, first: 10) {\n    edges {\n      node {\n        ... on Issue {\n          title\n          url\n          author {\n            login\n          }\n          createdAt\n          body\n          labels(first: 5) {\n            edges {\n              node {\n                name\n              }\n            }\n          }\n          comments {\n            totalCount\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '9',
        type: 'text',
        title: 'Magazine Style',
        description: 'Define the style of the feature announcement magazine',
        content:
          '✨💫 🌟 OPEN SOURCE NEWS FLASH 🌟 💫 ✨\n🚀 BREAKING UPDATES 🚀 EXCLUSIVE FEATURES 🎯 HOT RELEASES 🔥\n\nYour #1 source for hot new features in your favorite open source projects! 🌈',
        inputType: {
          type: 'text',
        },
      },
      {
        id: '10',
        type: 'prompt',
        title: 'Feature Magazine Content',
        description: 'Generate tabloid-style headlines focusing on new features',
        content:
          "You are a tech magazine writer specializing in new feature announcements. Create an exciting frontpage covering the latest features and enhancements from these repositories: {{repo1}}, {{repo2}}, and {{repo3}}.\n\nUse this data for each repository:\nRepository 1:\n- PRs: {{3}}\n- Issues: {{6}}\n\nRepository 2:\n- PRs: {{4}}\n- Issues: {{7}}\n\nRepository 3:\n- PRs: {{5}}\n- Issues: {{8}}\n\nStart with this header:\n{{9}}\n\nFor each repository:\n1. Create a section with an appropriate emoji\n2. Include 2-3 exciting headlines about new features or requests\n3. Focus on user impact and benefits\n4. Include the original URLs as 'READ MORE' links\n5. Mention scope of changes for PRs (additions + deletions)\n\nEnd with a 'FEATURE FORECAST' section comparing the most exciting upcoming features across repositories.\n\nFormat everything in markdown and use emojis liberally.",
      },
    ],
  },
}

const firstResponderSummaryExample: ExampleLoop = {
  altText: 'Battle Royale report',
  assetPath: '/images/modules/loops/FirstResponder.png',
  loop: {
    title: 'First Responder Activity Report',
    description:
      "Generates a summary of a first responder's activity including new issues, PR reviews, and issue involvement from the past week",
    nodes: [
      {
        id: '1',
        type: 'text',
        title: 'First Responder Username',
        description: 'GitHub username of the first responder',
        content: '',
        inputType: {
          type: 'text',
        },
      },
      {
        id: '2',
        type: 'text',
        title: 'Start Date',
        description: 'Start date for the report (1 week ago)',
        content: '2025-05-02',
        inputType: {
          type: 'text',
        },
      },
      {
        id: 'repo',
        type: 'text',
        title: 'Repository',
        description: 'The full repository name (e.g. owner/repo)',
        content: 'primer/react',
        inputType: {
          type: 'text',
        },
      },
      {
        id: '3',
        type: 'github-graphql',
        title: 'Created Issues',
        description: 'Issues created by the user in the past week',
        content:
          'query {\n  search(query: "repo:{{repo}} author:{{1}} is:issue created:>{{2}}", type: ISSUE, first: 100) {\n    edges {\n      node {\n        ... on Issue {\n          title\n          url\n          createdAt\n          state\n          labels(first: 5) {\n            edges {\n              node {\n                name\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '4',
        type: 'github-graphql',
        title: 'PR Reviews',
        description: 'PR reviews submitted by the user in the past week',
        content:
          'query {\n  search(query: "repo:{{repo}} is:pr reviewed-by:{{1}} updated:>{{2}}", type: ISSUE, first: 100) {\n    edges {\n      node {\n        ... on PullRequest {\n          title\n          url\n          reviews(first: 5, author: "{{1}}") {\n            edges {\n              node {\n                state\n                submittedAt\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: 'involved_issues',
        type: 'github-graphql',
        title: 'Involved Issues',
        description: 'Issues where the user was involved (commented or assigned) in the past week',
        content:
          'query {\n  search(query: "repo:{{repo}} involves:{{1}} is:issue updated:>{{2}}", type: ISSUE, first: 100) {\n    edges {\n      node {\n        ... on Issue {\n          title\n          url\n          updatedAt\n          state\n          comments(last: 5) {\n            nodes {\n              author {\n                login\n              }\n              createdAt\n            }\n          }\n          assignees(first: 5) {\n            nodes {\n              login\n            }\n          }\n        }\n      }\n    }\n  }\n}',
      },
      {
        id: '5',
        type: 'prompt',
        title: 'Activity Summary',
        description: "Summary report of the first responder's activity",
        content:
          "Generate a comprehensive summary report of the first responder's ({{1}}) activity in the {{repo}} repository over the past week. Include their issue creation, PR review activities, and issue involvement.\n\nIssues Created:\n{{3}}\n\nPR Reviews:\n{{4}}\n\nIssue Involvement:\n{{involved_issues}}\n\nPlease format the report with these sections:\n1. Overview (total numbers)\n2. Issue Activity\n   - Created Issues\n   - Issue Involvement (comments, assignments)\n3. PR Review Activity (highlight significant reviews)\n4. Key Observations\n\nKeep the tone professional and focus on what the next first responder needs to know about as they come in for the next shift.",
      },
    ],
  },
}

export const staffExamples: ExampleLoop[] = [battleRoyaleExample, firstResponderSummaryExample, githubGossipExample]
