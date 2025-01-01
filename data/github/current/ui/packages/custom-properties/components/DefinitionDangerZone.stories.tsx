import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {albumDefinition} from '../test-utils/mock-data'
import {DefinitionDangerZone} from './DefinitionDangerZone'

const meta: Meta = {
  title: 'Apps/Custom Properties/Components/DefinitionDangerZone',
  component: DefinitionDangerZone,
  decorators: [storyWrapper()],
  args: {
    definition: albumDefinition,
    canDelete: true,
    canPromote: false,
  },
} satisfies Meta<typeof DefinitionDangerZone>

export default meta

type Story = StoryObj<typeof DefinitionDangerZone>

export const Default: Story = {}

export const Promotable: Story = {
  args: {
    definition: {...albumDefinition, source: {type: 'org', name: 'Acme', slug: 'acme', avatarUrl: ''}},
    business: {name: 'Mega Corp.', slug: 'mega-corp'},
    canDelete: false,
    canPromote: true,
  },
}
