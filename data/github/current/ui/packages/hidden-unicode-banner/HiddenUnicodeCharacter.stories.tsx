import type {Meta} from '@storybook/react'
import {HiddenUnicodeCharacter} from './HiddenUnicodeCharacter'

const meta = {
  title: 'Recipes/HiddenUnicodeBanner',
  component: HiddenUnicodeCharacter,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof HiddenUnicodeCharacter>

export default meta

export const HiddenUnicodeCharacterExample = {
  render: () => <HiddenUnicodeCharacter char="U+202E" />,
}
