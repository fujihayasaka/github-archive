import type {Meta} from '@storybook/react'
import {
  ContrastSetting as ContrastSettingItem,
  type ContrastSettingProps,
  type ContrastSettingValue,
} from './ContrastSetting'
import {useCallback, useState} from 'react'

const meta: Meta = {
  title: 'Recipes/AppearanceSettings/ContrastSetting',
  component: ContrastSettingItem,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
}

export default meta

const ContrastSettingWrapper = () => {
  const [lightModeValue, setLightModeValue] = useState<ContrastSettingValue>('disabled')
  const [darkModeValue, setDarkModeValue] = useState<ContrastSettingValue>('disabled')

  const onChange: ContrastSettingProps['onChange'] = useCallback(contrastSettings => {
    if (contrastSettings.light !== undefined) {
      setLightModeValue(contrastSettings.light)
    }
    if (contrastSettings.dark !== undefined) {
      setDarkModeValue(contrastSettings.dark)
    }
  }, [])

  return <ContrastSettingItem lightModeValue={lightModeValue} darkModeValue={darkModeValue} onChange={onChange} />
}

export const ContrastSetting = {
  render: () => <ContrastSettingWrapper />,
}
