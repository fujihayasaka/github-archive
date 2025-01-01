import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {HiddenSelectionBanner} from './HiddenSelectionBanner'

const meta = {
  title: 'Recipes/ReposPicker/Components/HiddenSelectionBanner',
  component: HiddenSelectionBanner,
  decorators: [storyWrapper()],
} satisfies Meta<typeof HiddenSelectionBanner>

export default meta

export const One = {
  args: {
    hiddenSelectedCount: 1,
  },
}

export const TooMany = {
  args: {
    hiddenSelectedCount: 23456,
  },
}
