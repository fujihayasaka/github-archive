import {
  ContrastSetting,
  type ContrastSettingProps,
  type ContrastSettingValue,
} from '@github-ui/appearance-settings/ContrastSetting'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {Heading, Stack} from '@primer/react'
import {useCallback, useEffect, useState} from 'react'
import {ContrastSettingChangeEvent, type AppearanceFormElementChangeEvent} from './events'

type AppearanceSettingsProps = {
  initialLightModeValue?: ContrastSettingProps['lightModeValue']
  initialDarkModeValue?: ContrastSettingProps['darkModeValue']
}

export function AppearanceSettingsPage({
  initialLightModeValue = 'disabled',
  initialDarkModeValue = 'disabled',
}: AppearanceSettingsProps) {
  const [lightModeValue, setLightModeValue] = useState<ContrastSettingValue>(initialLightModeValue)
  const [darkModeValue, setDarkModeValue] = useState<ContrastSettingValue>(initialDarkModeValue)

  /** Update `ContrastSetting` when `appearance-form-element` changes */
  const changeListener = useCallback((event: AppearanceFormElementChangeEvent) => {
    const contrastSettings = event.detail

    if (contrastSettings.light !== undefined) {
      setLightModeValue(contrastSettings.light)
    }
    if (contrastSettings.dark !== undefined) {
      setDarkModeValue(contrastSettings.dark)
    }
  }, [])
  useEffect(() => {
    ssrSafeWindow?.addEventListener('appearance-form-element:change', changeListener)
    return () => {
      ssrSafeWindow?.removeEventListener('appearance-form-element:change', changeListener)
    }
  }, [changeListener])

  /** Update `appearance-form-element` when `ContrastSetting` changes */
  const onChange: ContrastSettingProps['onChange'] = useCallback(contrastSettings => {
    if (contrastSettings.light !== undefined) {
      setLightModeValue(contrastSettings.light)
    }
    if (contrastSettings.dark !== undefined) {
      setDarkModeValue(contrastSettings.dark)
    }

    if (!ssrSafeWindow) {
      return
    }
    const changeEvent = new ContrastSettingChangeEvent(contrastSettings)
    ssrSafeWindow.dispatchEvent(changeEvent)
  }, [])

  return (
    <Stack gap="spacious">
      <Stack gap="condensed">
        <Heading as="h2" variant="small">
          Contrast
        </Heading>
        <ContrastSetting lightModeValue={lightModeValue} darkModeValue={darkModeValue} onChange={onChange} />
      </Stack>
    </Stack>
  )
}
