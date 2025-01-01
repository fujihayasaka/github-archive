import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {useClientValue} from '@github-ui/use-client-value'
import {AlertIcon} from '@primer/octicons-react'
import {Button, Flash, Link} from '@primer/react'

export interface HiddenUnicodeBannerProps {
  isShown: boolean
  toggleShowHiddenCharacters: () => void
}

export function HiddenUnicodeBanner({isShown, toggleShowHiddenCharacters}: HiddenUnicodeBannerProps) {
  //doing it this way so that there are not hydration errors
  const [usableWindow] = useClientValue(() => ssrSafeWindow, ssrSafeWindow, [])

  if (!usableWindow) return null

  return (
    <Flash className="d-flex flex-items-center" full variant="warning">
      <AlertIcon />
      <span>
        This file contains bidirectional or hidden Unicode text that may be interpreted or compiled differently than
        what appears below. To review, open the file in an editor that reveals hidden Unicode characters.{' '}
        <Link inline href="https://github.co/hiddenchars" target="_blank" rel="noreferrer">
          Learn more about bidirectional Unicode characters
        </Link>
      </span>
      <Button
        className="ml-4 float-right"
        onClick={toggleShowHiddenCharacters}
        size="small"
        style={{backgroundClip: 'padding-box'}}
      >
        {isShown ? 'Hide revealed characters' : 'Show hidden characters'}
      </Button>
    </Flash>
  )
}
