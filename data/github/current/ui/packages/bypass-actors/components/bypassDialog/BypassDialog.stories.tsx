import type {Meta} from '@storybook/react'
import {BypassDialog, type BypassDialogProps} from './BypassDialog'
import {getBypassActor} from '../../test-utils/mock-data'
import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Recipes/BypassActors/BypassDialog',
  component: BypassDialog,
  parameters: {
    a11y: disableA11yRuleForDialog,
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof BypassDialog>

export default meta

// This override is required to mock the suggestions request.
global.fetch = async url => {
  if (url.toString().includes('suggestions')) {
    return new Response(JSON.stringify([getBypassActor(3, 'Team'), getBypassActor(4, 'Team')]))
  } else {
    return {ok: false, status: 404, json: async () => ({})} as Response
  }
}

const defaultArgs: Partial<BypassDialogProps> = {
  onClose: () => null,
  baseAvatarUrl: 'https://avatars.githubusercontent.com',
  enabledBypassActors: [],
  addBypassActor: () => null,
  initialSuggestions: [],
  suggestionsUrl: '/suggestions',
}

export const BypassDialogExample = {
  args: {
    ...defaultArgs,
    initialSuggestions: [getBypassActor(1, 'Team'), getBypassActor(2, 'Team')],
  },
  render: (args: BypassDialogProps) => <BypassDialog {...args} />,
}
