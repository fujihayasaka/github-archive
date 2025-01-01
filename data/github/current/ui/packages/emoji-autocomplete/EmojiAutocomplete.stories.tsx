import type {Meta} from '@storybook/react'
import {EmojiAutocomplete, type EmojiAutocompleteProps} from './EmojiAutocomplete'
import {FormControl, Textarea, TextInput} from '@primer/react'
import {KeybindingHint} from '@primer/react/experimental'

export default {
  title: 'Recipes/EmojiAutocomplete',
  component: EmojiAutocomplete,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    tone: {control: 'number'},
  },
} satisfies Meta<typeof EmojiAutocomplete>

export const SingleLineInput = {
  args: {
    tone: undefined,
  },
  render: (args: EmojiAutocompleteProps) => (
    <FormControl>
      <FormControl.Label>Example input</FormControl.Label>
      <FormControl.Caption>
        Use <KeybindingHint keys=":" /> to activate emoji menu.
      </FormControl.Caption>
      <EmojiAutocomplete {...args}>
        <TextInput />
      </EmojiAutocomplete>
    </FormControl>
  ),
}

export const MultiLineTextarea = {
  args: {
    tone: undefined,
  },
  render: (args: EmojiAutocompleteProps) => (
    <FormControl>
      <FormControl.Label>Example textarea</FormControl.Label>
      <FormControl.Caption>
        Use <KeybindingHint keys=":" /> to activate emoji menu.
      </FormControl.Caption>
      <EmojiAutocomplete {...args}>
        <Textarea />
      </EmojiAutocomplete>
    </FormControl>
  ),
}
