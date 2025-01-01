import {
  type PropsWithPartialAnchor,
  type ReactPartialAnchorProps,
  useExternalAnchor,
} from '@github-ui/react-core/react-partial-anchor'
import {ActionList, ActionMenu, Dialog} from '@primer/react'
import {useCallback, useState} from 'react'
import {getCookie, setCookie} from '@github-ui/cookies'
import {ControlGroup} from '@github-ui/control-group'

export type IncreaseContrastValues = 'sync_with_system' | 'enabled' | 'disabled'

interface AppearanceSettingsProps extends ReactPartialAnchorProps {}

export function AppearanceSettings(props: AppearanceSettingsProps) {
  if (props.reactPartialAnchor) {
    return <ExternallyAnchoredAppearanceSettings {...props} reactPartialAnchor={props.reactPartialAnchor} />
  }

  return null
}

function ExternallyAnchoredAppearanceSettings(props: PropsWithPartialAnchor<AppearanceSettingsProps>) {
  const {ref: anchorRef, open, setOpen} = useExternalAnchor(props.reactPartialAnchor)

  return open ? (
    <Dialog title="Appearance settings" onClose={() => setOpen(false)} returnFocusRef={anchorRef} width="large">
      <AppearanceSettingsPane />
    </Dialog>
  ) : null
}

export function AppearanceSettingsPane() {
  const initialLightModeValue = (getCookie('increase_contrast_light')?.value ??
    'sync_with_system') as IncreaseContrastValues
  const [lightModeValue, _setLightModeValue] = useState(initialLightModeValue)
  const setLightModeValue = useCallback((newValue: IncreaseContrastValues) => {
    _setLightModeValue(newValue)
    setCookie('increase_contrast_light', newValue)
  }, [])

  const initialDarkModeValue = (getCookie('increase_contrast_dark')?.value ??
    'sync_with_system') as IncreaseContrastValues
  const [darkModeValue, _setDarkModeValue] = useState(initialDarkModeValue)
  const setDarkModeValue = useCallback((newValue: IncreaseContrastValues) => {
    _setDarkModeValue(newValue)
    setCookie('increase_contrast_dark', newValue)
  }, [])

  const getValue = useCallback(() => {
    if (lightModeValue === 'disabled' && darkModeValue === 'disabled') {
      // Case: Both theme settings are "disabled".
      // => The increase contrast setting is "disabled".
      return 'disabled'
    } else if (lightModeValue === 'enabled' || darkModeValue === 'enabled') {
      // Case: One or both theme settings is "enabled".
      // => The increase contrast setting is "enabled".
      return 'enabled'
    } else {
      // Case: One or both theme settings is "sync_with_system", or
      // Case: Both theme settings are unset.
      // => The increase contrast setting is "sync_with_system".
      return 'sync_with_system'
    }
  }, [lightModeValue, darkModeValue])

  const toggleLightModeValue = useCallback(() => {
    if (lightModeValue !== 'disabled') {
      // Case: Toggling off
      setLightModeValue('disabled')
    } else {
      // Case: Toggling on
      setLightModeValue(getValue() === 'disabled' ? 'enabled' : getValue())
    }
  }, [lightModeValue, setLightModeValue, getValue])
  const toggleDarkModeValue = useCallback(() => {
    if (darkModeValue !== 'disabled') {
      // Case: Toggling off
      setDarkModeValue('disabled')
    } else {
      // Case: Toggling on
      setDarkModeValue(getValue() === 'disabled' ? 'enabled' : getValue())
    }
  }, [darkModeValue, setDarkModeValue, getValue])

  const options: {[key in IncreaseContrastValues]: {name: string}} = {
    sync_with_system: {name: 'Sync with system'},
    enabled: {name: 'Enabled'},
    disabled: {name: 'Disabled'},
  }

  return (
    <ControlGroup>
      <ControlGroup.Item>
        <ControlGroup.Title id="increase-contrast-label">Increase contrast</ControlGroup.Title>
        <ControlGroup.Description>
          <span id="increase-contrast-description">
            Enable high contrast for a single theme or for both light and dark mode
          </span>
        </ControlGroup.Description>
        <ControlGroup.Custom>
          <ActionMenu>
            <ActionMenu.Button
              id="increase-contrast-button"
              aria-labelledby="increase-contrast-label increase-contrast-button"
              aria-describedby="increase-contrast-description"
            >
              {options[getValue()].name}
            </ActionMenu.Button>
            <ActionMenu.Overlay width="medium">
              <ActionList selectionVariant="single">
                {Object.entries(options).map(([key, {name}]) => (
                  <ActionList.Item
                    key={key}
                    selected={getValue() === key}
                    onSelect={() => {
                      setLightModeValue(key as IncreaseContrastValues)
                      setDarkModeValue(key as IncreaseContrastValues)
                    }}
                  >
                    {name}
                  </ActionList.Item>
                ))}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </ControlGroup.Custom>
      </ControlGroup.Item>
      <ControlGroup.Item nestedLevel={1}>
        <ControlGroup.Title id="light-mode-label">Light mode</ControlGroup.Title>
        <ControlGroup.ToggleSwitch
          aria-labelledby="light-mode-label"
          checked={lightModeValue !== 'disabled'}
          onClick={toggleLightModeValue}
        />
      </ControlGroup.Item>
      <ControlGroup.Item nestedLevel={1}>
        <ControlGroup.Title id="dark-mode-label">Dark mode</ControlGroup.Title>
        <ControlGroup.ToggleSwitch
          aria-labelledby="dark-mode-label"
          checked={darkModeValue !== 'disabled'}
          onClick={toggleDarkModeValue}
        />
      </ControlGroup.Item>
    </ControlGroup>
  )
}
