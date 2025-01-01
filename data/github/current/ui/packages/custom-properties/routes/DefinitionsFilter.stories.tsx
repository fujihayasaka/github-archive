import type {Meta} from '@storybook/react'

import {DefinitionsFilter} from './DefinitionsFilter'

const meta: Meta = {
  title: 'Apps/Custom Properties/Components/DefinitionsFilter',
  component: DefinitionsFilter,
}

export default meta

export const OrgLevel = {}

export const BusinessLevel = {
  args: {
    businessSlug: 'corp',
  },
}
