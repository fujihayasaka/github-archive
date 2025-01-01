import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {ListItemRepoIcon} from './ListItemRepoIcon'

const meta = {
  title: 'Recipes/ReposPicker/Components/ListItemRepoIcon',
  component: ListItemRepoIcon,
  decorators: [storyWrapper()],
  args: {
    visibility: 'public',
  },
} satisfies Meta<typeof ListItemRepoIcon>

export default meta

export const Default = {}
