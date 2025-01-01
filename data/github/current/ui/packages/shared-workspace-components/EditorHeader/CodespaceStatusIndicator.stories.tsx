import {noop} from '@github-ui/noop'
import {CodespaceStatusIndicator} from './CodespaceStatusIndicator'
import type {Meta} from '@storybook/react'

const meta: Meta = {
  title: 'Recipes/CodespaceStatusIndicator',
  component: CodespaceStatusIndicator,
  args: {
    codespaceState: 'none',
    onDetailsClick: noop,
  },
}

export default meta

export const Example = {}
