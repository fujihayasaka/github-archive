import type {ReactPartialAnchorProps} from '@github-ui/react-core/react-partial-anchor'
import type {ReactPartialAnchorElement} from '@github-ui/react-partial-anchor-element'
import type {Meta} from '@storybook/react'
import {useRef, useState, useEffect} from 'react'
import {AppearanceSettings} from './AppearanceSettingsDialog'
import {AppearanceSettingsNavButton} from './components/AppearanceSettingsNavButton'

const meta: Meta = {
  title: 'Recipes/AppearanceSettings/AppearanceSettingsDialog',
  component: AppearanceSettings,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
}

export default meta

export function AppearanceSettingsDialog() {
  const anchorRef = useRef<HTMLButtonElement>(null)

  // AppearanceSettings expects an external anchor (e.g. from `<react-partial-anchor>`),
  // but external anchors are connected-up using Rails helpers that aren’t available in Storybook,
  // so fake something that satisfies the same contract.
  const [reactPartialAnchor, setReactPartialAnchor] = useState<ReactPartialAnchorProps['reactPartialAnchor']>()
  useEffect(() => {
    if (anchorRef.current) {
      setReactPartialAnchor({__wrapperElement: {anchor: anchorRef.current} as unknown as ReactPartialAnchorElement})
    }
  }, [anchorRef, setReactPartialAnchor])

  return (
    <div style={{height: '100px', backgroundColor: 'black', padding: '1rem'}}>
      <AppearanceSettingsNavButton ref={anchorRef} />
      {reactPartialAnchor ? <AppearanceSettings reactPartialAnchor={reactPartialAnchor} /> : null}
    </div>
  )
}
