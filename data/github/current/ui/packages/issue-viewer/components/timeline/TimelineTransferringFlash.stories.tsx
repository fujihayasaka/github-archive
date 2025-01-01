import type {Meta} from '@storybook/react'
import {TimelineTransferringFlash} from './TimelineTransferringFlash'

const meta = {
  title: 'IssueViewer/Timeline transferring Flash',
  component: TimelineTransferringFlash,
} satisfies Meta<typeof TimelineTransferringFlash>

export default meta

export const Example = () => <TimelineTransferringFlash />
