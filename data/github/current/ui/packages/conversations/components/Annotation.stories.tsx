import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'

import type {DiffAnnotation} from '../types'
import {Annotation} from './Annotation'

const meta: Meta<typeof Annotation> = {
  title: 'Apps/React Shared/Conversations/Annotation',
  component: Annotation,
  decorators: [
    S => (
      <Box sx={{width: 'clamp(240px, 100vw, 540px)'}}>
        <S />
      </Box>
    ),
  ],
}

type Story = StoryObj<typeof Annotation>

export const Story = {
  argTypes: {
    annotationLevel: {
      options: ['FAILURE', 'WARNING', 'NOTICE'],
      control: {type: 'select'},
    },
  },
  args: {
    id: 1,
    annotationLevel: 'FAILURE',
    startLine: 1,
    endLine: 1,
    message:
      // eslint-disable-next-line github/unescaped-html-literal
      '<div>Workflow run:        <a href="https://github.localhost/monalisa/smile/actions/runs/1234567890" class="link-gray" rel="noreferrer noopener" data-test-selector="linkified">https://github.localhost/monalisa/smile/actions/runs/1234567890</a> [workflow_dispatch][full]\nDecision and reason: Full run is needed based on event (workflow_dispatch)</div>',
    path: 'file.md',
    title: 'check annotation title',
    checkRun: {
      name: 'check-run-name',
      detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/1',
    },
    appAvatarAltText: 'check-suite-app-name avatar image',
    appAvatarUrl: 'http://alambic.github.localhost/avatars/u/2?size=48',
    checkSuiteName: 'check-suite-name',
  },
  render: (args: DiffAnnotation) => <Annotation annotation={args} />,
}

export default meta
