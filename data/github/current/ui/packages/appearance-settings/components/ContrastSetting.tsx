import {useCallback} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import styles from './ContrastSetting.module.css'

export type ContrastSettingValue = 'enabled' | 'disabled'

export type ContrastSettingProps = {
  lightModeValue: ContrastSettingValue
  darkModeValue: ContrastSettingValue

  /** Callback that is called when the contrast setting is changed */
  onChange: (values: {light?: ContrastSettingValue; dark?: ContrastSettingValue}) => void
  border?: boolean
}

export function ContrastSetting({lightModeValue, darkModeValue, onChange, border = true}: ContrastSettingProps) {
  const getValue = useCallback((): ContrastSettingValue => {
    if (lightModeValue === 'enabled' || darkModeValue === 'enabled') {
      // Case: One or both theme settings is "enabled".
      // => The increase contrast setting is "enabled".
      return 'enabled'
    } else {
      // Case: Both theme settings are "disabled".
      // => The increase contrast setting is "disabled".
      return 'disabled'
    }
  }, [lightModeValue, darkModeValue])

  const toggleLightModeValue = useCallback(() => {
    const newValue = lightModeValue === 'enabled' ? 'disabled' : 'enabled'
    onChange({light: newValue})
  }, [lightModeValue, onChange])

  const toggleDarkModeValue = useCallback(() => {
    const newValue = darkModeValue === 'enabled' ? 'disabled' : 'enabled'
    onChange({dark: newValue})
  }, [darkModeValue, onChange])

  const toggleValue = useCallback(() => {
    const newValue = getValue() === 'enabled' ? 'disabled' : 'enabled'
    onChange({light: newValue, dark: newValue})
  }, [getValue, onChange])

  return (
    <ControlGroup border={border}>
      <ControlGroup.Item contentsClassname={styles.ControlGroupFix}>
        <ControlGroup.Title id="increase-contrast-label">Increase contrast</ControlGroup.Title>
        <ControlGroup.Description>
          <span id="increase-contrast-description">
            Enable high contrast for light or dark mode (or both) based on your system settings
          </span>
        </ControlGroup.Description>
        <ControlGroup.ToggleSwitch
          aria-labelledby="increase-contrast-label"
          aria-describedby="increase-contrast-description"
          checked={getValue() === 'enabled'}
          onClick={toggleValue}
        />
      </ControlGroup.Item>
      <ControlGroup.Item nestedLevel={1} contentsClassname={styles.ControlGroupFix}>
        <ControlGroup.Title id="light-mode-label">Light mode</ControlGroup.Title>
        <ControlGroup.ToggleSwitch
          aria-labelledby="light-mode-label"
          checked={lightModeValue === 'enabled'}
          onClick={toggleLightModeValue}
        />
      </ControlGroup.Item>
      <ControlGroup.Item nestedLevel={1} contentsClassname={styles.ControlGroupFix}>
        <ControlGroup.Title id="dark-mode-label">Dark mode</ControlGroup.Title>
        <ControlGroup.ToggleSwitch
          aria-labelledby="dark-mode-label"
          checked={darkModeValue === 'enabled'}
          onClick={toggleDarkModeValue}
        />
      </ControlGroup.Item>
    </ControlGroup>
  )
}
