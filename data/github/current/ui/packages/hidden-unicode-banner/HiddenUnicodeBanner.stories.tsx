import type {Meta} from '@storybook/react'
import {HiddenUnicodeBanner} from './HiddenUnicodeBanner'
import {useState} from 'react'

const meta = {
  title: 'Recipes/HiddenUnicodeBanner',
  component: HiddenUnicodeBanner,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof HiddenUnicodeBanner>

export default meta

export const HiddenUnicodeBannerExample = {
  render: () => {
    // eslint-disable-next-line react-hooks/rules-of-hooks
    const [isHiddenUnicode, setIsHiddenUnicode] = useState(false)
    return (
      <HiddenUnicodeBanner
        isShown={isHiddenUnicode}
        toggleShowHiddenCharacters={() => setIsHiddenUnicode(!isHiddenUnicode)}
      />
    )
  },
}
