import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {DefinitionsFilter} from './DefinitionsFilter'

const meta: Meta = {
  title: 'Apps/Custom Properties/Components/DefinitionsFilter',
  component: DefinitionsFilter,
  decorators: [
    (Story, {args}) => (
      <Wrapper appPayload={{['enabled_features']: {['custom_property_definitions_required_filter']: true}}}>
        <Story {...args} />
      </Wrapper>
    ),
  ],
}

export default meta

export const OrgLevel = {}

export const BusinessLevel = {
  args: {
    businessSlug: 'corp',
  },
}
