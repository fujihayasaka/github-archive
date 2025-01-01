import {todayString, tomorrowString} from '../helpers/dates'

interface ClipboardCell {
  plain: string | number
  html: string | undefined | number
}

type ClipboardData = {
  [key: string]: Array<ClipboardCell>
}

// Data from integrationTestsWithItems: https://ui.githubapp.com/orgs/integration/projects/1
// When adding a new column, add a new key for the column where it appears in the table.
// The key should match the header of the respective column as it appears in table, for example: 'Linked pull requests'
// For each key, include an array of objects with `plain` and `html` properties, each representing
// the expected clipboard value of the cell in that column for each row.
export const clipboardData: ClipboardData = {
  Title: [
    {
      plain:
        "This is the title for my closed issue. Now that I've closed it, the text is really and long and should elide!",
      html: '<a href="https://github.com/github/memex/issues/336">This is the title for my closed issue. Now that I\'ve closed it, the text is really and long and should elide!</a>',
    },
    {
      plain: 'Update styles for table',
      html: '<a href="https://github.com/github/memex/pull/337">Update styles for table</a>',
    },
    {
      plain: 'Here is a Draft Issue!',
      html: 'Here is a Draft Issue!',
    },
    {
      plain: 'This is a closed issue for testing',
      html: '<a href="https://github.com/github/memex/issues/101">This is a closed issue for testing</a>',
    },
    {
      plain: 'Fix this `issue` please!',
      html: '<a href="https://github.com/github/memex/issues/336">Fix this <code>issue</code> please!</a>',
    },
    {
      plain: 'Fixes all the bugs',
      html: '<a href="https://github.com/github/memex/pull/337">Fixes all the bugs</a>',
    },
    {
      plain: 'https://google.com',
      html: '<a href="https://google.com/" target="_blank" rel="noopener noreferrer">https://google.com</a>',
    },
  ],
  URL: [
    {
      plain: 'https://github.com/github/memex/issues/336',
      html: undefined,
    },
    {
      plain: 'https://github.com/github/memex/pull/337',
      html: undefined,
    },
    {
      plain: '',
      html: undefined,
    },
    {
      plain: 'https://github.com/github/memex/issues/101',
      html: undefined,
    },
    {
      plain: 'https://github.com/github/memex/issues/336',
      html: undefined,
    },
    {
      plain: 'https://github.com/github/memex/pull/337',
      html: undefined,
    },
    {
      plain: '',
      html: undefined,
    },
  ],
  Assignees: [
    {plain: 'dmarcey, iansan5653', html: 'dmarcey, iansan5653'},
    {plain: 'mikesurowiec', html: 'mikesurowiec'},
    {plain: '', html: ''},
    {plain: 'lerebear', html: 'lerebear'},
    {plain: 'traumverloren', html: 'traumverloren'},
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  Status: [
    {plain: 'Done', html: 'Done'},
    {plain: 'Done', html: 'Done'},
    {plain: '', html: ''},
    {plain: 'Done', html: 'Done'},
    {plain: 'Backlog', html: 'Backlog'},
    {plain: 'Backlog', html: 'Backlog'},
    {plain: '', html: ''},
  ],
  Labels: [
    {
      plain: 'enhancement ✨, tech debt',
      html: 'enhancement <g-emoji fallback-src="http://assets.github.com/images/icons/emoji/unicode/2728.png" alias="sparkles" class="g-emoji">✨</g-emoji>, tech debt',
    },
    {plain: '', html: ''},
    {plain: '', html: ''},
    {
      plain: 'enhancement ✨',
      html: 'enhancement <g-emoji fallback-src="http://assets.github.com/images/icons/emoji/unicode/2728.png" alias="sparkles" class="g-emoji">✨</g-emoji>',
    },
    {
      plain: 'enhancement ✨',
      html: 'enhancement <g-emoji fallback-src="http://assets.github.com/images/icons/emoji/unicode/2728.png" alias="sparkles" class="g-emoji">✨</g-emoji>',
    },
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  Repository: [
    {plain: 'github/memex', html: '<a href="https://github.com/github/memex">github/memex</a>'},
    {plain: 'github/memex', html: '<a href="https://github.com/github/memex">github/memex</a>'},
    {plain: '', html: ''},
    {plain: 'github/memex', html: '<a href="https://github.com/github/memex">github/memex</a>'},
    {plain: 'github/memex', html: '<a href="https://github.com/github/memex">github/memex</a>'},
    {plain: 'github/memex', html: '<a href="https://github.com/github/memex">github/memex</a>'},
    {plain: '', html: ''},
  ],
  Milestone: [
    {
      plain: 'v0.1 - Prioritized Lists?',
      html: '<a href="https://github.com/github/memex/milestone/2">v0.1 - Prioritized Lists?</a>',
    },
    {plain: '', html: ''},
    {plain: '', html: ''},
    {
      plain: 'v0.1 - Prioritized Lists?',
      html: '<a href="https://github.com/github/memex/milestone/2">v0.1 - Prioritized Lists?</a>',
    },
    {
      plain: 'Sprint 9',
      html: '<a href="https://github.com/github/memex/milestone/4">Sprint 9</a>',
    },
    {
      plain: 'v0.1 - Prioritized Lists?',
      html: '<a href="https://github.com/github/memex/milestone/2">v0.1 - Prioritized Lists?</a>',
    },
    {plain: '', html: ''},
  ],
  'Linked pull requests': [
    {
      plain: 'https://github.com/github/memex/issues/1234',
      html: '<a href="https://github.com/github/memex/issues/1234">#1234</a>',
    },
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {
      plain:
        'https://github.com/github/memex/issues/123, https://github.com/github/memex/issues/456, https://github.com/github/memex/issues/789',
      html: '<a href="https://github.com/github/memex/issues/123">#123</a>, <a href="https://github.com/github/memex/issues/456">#456</a>, <a href="https://github.com/github/memex/issues/789">#789</a>',
    },
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  Type: [
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: 'Batch', html: 'Batch'},
    {plain: 'Bug', html: 'Bug'},
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  Reviewers: [
    {plain: '', html: ''},
    {plain: 'dmarcey, Memex Team 1', html: 'dmarcey, Memex Team 1'},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  'Parent issue': [
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {
      plain: 'http://github.localhost:80/github/sriracha-4/issues/14',
      html: '<a href="http://github.localhost/github/sriracha-4/issues/14">github/sriracha-4#10</a>',
    },
    {
      plain: 'http://github.localhost:80/github/sriracha-4/issues/14',
      html: '<a href="http://github.localhost/github/sriracha-4/issues/14">github/sriracha-4#10</a>',
    },
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  'Sub-issues progress': [
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '2 / 6 (33%)', html: '2 / 6 (33%)'},
    {plain: '2 / 6 (33%)', html: '2 / 6 (33%)'},
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  Stage: [
    {plain: '', html: ''},
    {plain: 'Closed', html: 'Closed'},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: 'Up Next', html: 'Up Next'},
    {plain: '', html: ''},
  ],
  Team: [
    {plain: 'Novelty Aardvarks', html: 'Novelty Aardvarks'},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: 'Design Systems', html: 'Design Systems'},
    {plain: 'Novelty Aardvarks', html: 'Novelty Aardvarks'},
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  Estimate: [
    {plain: 10, html: 10},
    {plain: 10, html: 10},
    {plain: '', html: ''},
    {plain: 3, html: 3},
    {plain: 1, html: 1},
    {plain: '', html: ''},
    {plain: '', html: ''},
  ],
  'Due Date': [
    {plain: todayString, html: todayString},
    {plain: '', html: ''},
    {plain: '', html: ''},
    {plain: todayString, html: todayString},
    {plain: '', html: ''},
    {plain: tomorrowString, html: tomorrowString},
    {plain: '', html: ''},
  ],
}
