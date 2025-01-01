import type {Meta} from '@storybook/react'
import type {ComponentProps} from 'react'

import {OrgConflictsDialog} from './OrgConflictsDialog'

type StoryArgs = ComponentProps<typeof OrgConflictsDialog>

const avatarUrl = 'https://avatars.githubusercontent.com/b/199424?s=60&v=4'
const sampleProps: ComponentProps<typeof OrgConflictsDialog> = {
  onClose: () => undefined,
  orgConflicts: {
    totalUsageCount: 100,
    usages: [
      {name: 'github', propertyType: 'string', avatarUrl},
      {name: 'maximum-effort', propertyType: 'single_select', avatarUrl},
      {name: 'minimum-effort', propertyType: 'multi_select', avatarUrl},
      {name: 'properties-game', propertyType: 'true_false', avatarUrl},
    ],
  },
  title: 'Cannot promote to enterprise',
  displayMessage: 'This property cannot be promoted to MegaCorp Inc. because there are conflicting properties',
}

const meta: Meta<StoryArgs> = {
  title: 'Apps/Custom Properties/Components/OrgConflictsDialog',
  component: OrgConflictsDialog,
  args: sampleProps,
}

export default meta

export const Default = {}
