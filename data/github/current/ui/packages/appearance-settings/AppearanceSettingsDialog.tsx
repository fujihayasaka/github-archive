import {getCookie, setCookie} from '@github-ui/cookies'
import {
  type PropsWithPartialAnchor,
  type ReactPartialAnchorProps,
  useExternalAnchor,
} from '@github-ui/react-core/react-partial-anchor'
import {Dialog} from '@primer/react'
import {useCallback, useState} from 'react'
import {ContrastSetting, type ContrastSettingProps, type ContrastSettingValue} from './components/ContrastSetting'
import {ssrSafeDocument} from '@github-ui/ssr-utils'

function updateThemeAttribute(attribute: 'data-light-theme' | 'data-dark-theme', value: ContrastSettingValue) {
  const theme = ssrSafeDocument?.documentElement.getAttribute(attribute)
  if (!theme) {
    return
  }
  if (value === 'enabled' && !theme.endsWith('_high_contrast')) {
    // Switch to the increased-contrast version of the theme
    ssrSafeDocument?.documentElement.setAttribute(attribute, `${theme}_high_contrast`)
  } else if (value === 'disabled' && theme.endsWith('_high_contrast')) {
    // Switch to the default-contrast version of the theme
    ssrSafeDocument?.documentElement.setAttribute(attribute, theme.replace(/_high_contrast$/, ''))
  }
}

interface AppearanceSettingsProps extends ReactPartialAnchorProps {}

export function AppearanceSettings(props: AppearanceSettingsProps) {
  if (props.reactPartialAnchor) {
    return <ExternallyAnchoredAppearanceSettings {...props} reactPartialAnchor={props.reactPartialAnchor} />
  }

  return null
}

function ExternallyAnchoredAppearanceSettings(props: PropsWithPartialAnchor<AppearanceSettingsProps>) {
  const {ref: anchorRef, open, setOpen} = useExternalAnchor(props.reactPartialAnchor)

  const initialLightModeValue = (getCookie('increase_contrast_light')?.value as ContrastSettingValue) ?? 'disabled'
  const [lightModeValue, setLightModeValue] = useState<ContrastSettingValue>(initialLightModeValue)

  const initialDarkModeValue = (getCookie('increase_contrast_dark')?.value as ContrastSettingValue) ?? 'disabled'
  const [darkModeValue, setDarkModeValue] = useState<ContrastSettingValue>(initialDarkModeValue)

  const onChange: ContrastSettingProps['onChange'] = useCallback(values => {
    if (values.light !== undefined) {
      setLightModeValue(values.light)
      setCookie('increase_contrast_light', values.light)
      updateThemeAttribute('data-light-theme', values.light)
    }
    if (values.dark !== undefined) {
      setDarkModeValue(values.dark)
      setCookie('increase_contrast_dark', values.dark)
      updateThemeAttribute('data-dark-theme', values.dark)
    }
  }, [])

  function CustomBody() {
    return (
      <Dialog.Body className="px-0 py-1">
        <ContrastSetting
          onChange={onChange}
          lightModeValue={lightModeValue}
          darkModeValue={darkModeValue}
          border={false}
        />
      </Dialog.Body>
    )
  }

  return open ? (
    <Dialog
      title="Appearance settings"
      onClose={() => setOpen(false)}
      returnFocusRef={anchorRef}
      width="large"
      renderBody={CustomBody}
    />
  ) : null
}
