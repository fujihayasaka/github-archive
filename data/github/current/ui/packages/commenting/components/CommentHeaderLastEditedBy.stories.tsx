import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {graphql} from 'react-relay'

import type {CommentHeaderLastEditedByQuery} from './__generated__/CommentHeaderLastEditedByQuery.graphql'
import {CommentHeaderLastEditedBy} from './CommentHeaderLastEditedBy'

// This query will be used to fetch the last edited information for a comment
const CommentHeaderLastEditedByNode = graphql`
  query CommentHeaderLastEditedByQuery($id: ID!) @relay_test_operation {
    node(id: $id) {
      ... on Comment {
        # eslint-disable-next-line relay/must-colocate-fragment-spreads
        ...MarkdownEditHistoryViewer_comment
        # eslint-disable-next-line relay/must-colocate-fragment-spreads
        ...MarkdownLastEditedBy
      }
    }
  }
`

type CommentHeaderLastEditedByQueries = {
  followUpQuery: CommentHeaderLastEditedByQuery
}

const meta = {
  title: 'Commenting/CommentHeaderLastEditedBy',
  component: CommentHeaderLastEditedBy,
  parameters: {
    controls: {expanded: true},
    docs: {
      description: {
        component: 'Component that displays when a comment was last edited and by whom.',
      },
    },
  },
  tags: ['autodocs'],
} satisfies Meta<typeof CommentHeaderLastEditedBy>

export default meta
export const Default: RelayStoryObj<typeof CommentHeaderLastEditedBy, CommentHeaderLastEditedByQueries> = {
  decorators: [
    (story, context) =>
      relayDecorator<typeof CommentHeaderLastEditedBy, CommentHeaderLastEditedByQueries>(story, context),
  ],
  args: {
    id: 'comment_123',
  },
  parameters: {
    relay: {
      queries: {
        followUpQuery: {
          type: 'fragment',
          query: CommentHeaderLastEditedByNode,
          variables: {
            id: 'comment_123',
          },
        },
      },
    },
    docs: {
      description: {
        story: 'Shows the last edited information with editor username.',
      },
    },
  },
}
