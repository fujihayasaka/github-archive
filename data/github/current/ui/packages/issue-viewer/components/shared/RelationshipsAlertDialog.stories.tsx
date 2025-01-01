import {noop} from '@github-ui/noop'
import {RelationshipsAlertDialog, type RelationshipsAlertDialogProps} from './RelationshipsAlertDialog'
import type {Meta} from '@storybook/react'

const meta = {
  title: 'Apps/Sub Issues',
  component: RelationshipsAlertDialog,
} satisfies Meta<typeof RelationshipsAlertDialog>

export default meta

const args = {
  title: 'Are you sure?',
  children: 'This action cannot be undone.',
  onClose: noop,
} satisfies RelationshipsAlertDialogProps

export const RelationshipsAlertDialogExample = {args}
