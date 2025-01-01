import type {HypersightPayload} from '../routes/Hypersight'

export function getHypersightRoutePayload(): HypersightPayload {
  return {
    pullRequest: {
      number: 1,
      title: 'Example PR',
      user: {
        login: 'octocat',
        id: 583231,
        avatar_url: 'https://avatars.githubusercontent.com/u/583231?v=4',
      },
      created_at: '2023-10-01T00:00:00Z',
      updated_at: '2023-10-01T00:00:00Z',
      state: 'open',
      html_url: 'https://github.com/example/repo/pull/1',
      id: 1,
      body: 'This is an example PR.',
      changed_files: 5,
      commits: 3,
      base: {
        ref: 'main',
        repo: {
          name: 'example-repo',
          owner: {login: 'octocat'},
        },
      },
      head: {
        ref: 'feature-branch',
        repo: {
          name: 'example-repo',
          owner: {login: 'octocat'},
        },
      },
    },
    apiUrl: 'http://example.com',
    diffs: {
      CODE: [
        {
          diffLines: [
            {type: 'HUNK', text: '@@ -1 +1 @@', left: 1, right: 1, html: '@@ -1 +1 @@'},
            {type: 'DELETION', text: 'Hello World', left: 1, right: null, html: '&lt;span&gt;Hello World&lt;/span&gt;'},
            {
              type: 'ADDITION',
              text: 'Hello GitHub',
              left: null,
              right: 1,
              html: '&lt;span&gt;Hello GitHub&lt;/span&gt;',
            },
          ],
          isBinary: false,
          isTooBig: false,
          path: 'file.txt',
          status: 'MODIFIED',
        },
      ],
      DOCUMENTATION: [],
      DATA: [],
      DEPENDENCY_MANAGEMENT: [],
      BINARY: [],
      GENERATED: [],
      TESTS: [],
      VENDORED: [],
      UNCATEGORIZED: [],
    },
    mentionedIssues: [],
    urls: {
      files: '/files',
      conversation: '/conversation',
      commits: '/commits',
      checks: '/checks',
      walkthrough: '/walkthrough',
    },
  }
}
