import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulAnimatedVideo} from './ContentfulAnimatedVideo'

const meta: Meta<typeof ContentfulAnimatedVideo> = {
  title: 'Mkt/Swp/Contentful/ContentfulAnimatedVideo',
  component: ContentfulAnimatedVideo,
}

export default meta

type Story = StoryObj<typeof ContentfulAnimatedVideo>

export const Default: Story = {
  args: {
    component: {
      sys: {
        id: '22OkwBbZSnP7hwHdMsbhlA',
        contentType: {
          sys: {
            id: 'animatedVideo',
          },
        },
      },
      fields: {
        video: {
          fields: {
            description: 'This is a video showing how to use copilot in vscode',
            file: {
              url: 'https://github.githubassets.com/assets/hero-lg-a0288ef877a1.mp4',
            },
          },
        },
        playLabel: 'Click to play',
        pauseLabel: 'Click to pause',
        replayLabel: 'Click to replay',
      },
    },
  },
}
