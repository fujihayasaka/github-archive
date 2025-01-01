import {noop} from '@github-ui/noop'
import type {Meta} from '@storybook/react'

import {ReactionViewerBase} from './ReactionViewerBase'
import type {ReactionViewerGroup} from './utils/ReactionGroups'

const meta = {
  title: 'ReactionViewerBase',
  component: ReactionViewerBase,
  decorators: [
    Story => (
      <div className="m-5">
        <Story />
      </div>
    ),
  ],
} satisfies Meta<typeof ReactionViewerBase>

export default meta

export const Example = {
  render: () => {
    const reactionGroups: ReactionViewerGroup[] = [
      {
        reaction: {content: 'THUMBS_UP', viewerHasReacted: true},
        reactors: [
          {
            login: 'monalisa',
            typeName: 'User',
          },
        ],
        totalCount: 1,
      },
      {reaction: {content: 'THUMBS_DOWN', viewerHasReacted: false}, reactors: [], totalCount: 0},
      {reaction: {content: 'LAUGH', viewerHasReacted: false}, reactors: [], totalCount: 0},
      {reaction: {content: 'HOORAY', viewerHasReacted: false}, reactors: [], totalCount: 0},
      {reaction: {content: 'CONFUSED', viewerHasReacted: true}, reactors: [], totalCount: 0},
      {reaction: {content: 'HEART', viewerHasReacted: false}, reactors: [], totalCount: 0},
      {reaction: {content: 'ROCKET', viewerHasReacted: false}, reactors: [], totalCount: 0},
      {reaction: {content: 'EYES', viewerHasReacted: false}, reactors: [], totalCount: 0},
    ]

    return <ReactionViewerBase reactionGroups={reactionGroups} onReact={noop} />
  },
}
