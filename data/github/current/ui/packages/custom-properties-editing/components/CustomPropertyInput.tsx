import type {ValueType} from '@github-ui/custom-properties-types'
import {getEmptyValueByType} from '@github-ui/custom-properties-types/helpers'
import {TextInput} from '@primer/react'
import type {HTMLAttributes} from 'react'

import {CustomPropertyBooleanSelect} from './CustomPropertyBooleanSelect'
import type {CustomPropertySelectPanelProps} from './CustomPropertySelectPanel'
import {
  CustomPropertyMultiSelectPanel,
  CustomPropertySingleSelectPanel,
  mixedValuePlaceholder,
} from './CustomPropertySelectPanel'

interface CustomPropertyInputProps extends CustomPropertySelectPanelProps {
  valueType: ValueType
  // TODO remove with custom_properties_edit_modal
  hideDefaultPlaceholder?: boolean
  orgName: string
  booleanMenuEnabled?: boolean
  inputProps?: HTMLAttributes<HTMLInputElement>
}

export function CustomPropertyInput(props: CustomPropertyInputProps) {
  const {valueType, defaultValue} = props
  const value = props.propertyValue || getEmptyValueByType(valueType)

  switch (valueType) {
    case 'single_select':
      return <CustomPropertySingleSelectPanel {...props} propertyValue={value as string} />
    case 'multi_select':
      return <CustomPropertyMultiSelectPanel {...props} propertyValue={value as string[]} />
    case 'true_false':
      return props.booleanMenuEnabled ? (
        <CustomPropertyBooleanSelect {...props} defaultValue={defaultValue as string} propertyValue={value as string} />
      ) : (
        <CustomPropertySingleSelectPanel {...props} allowedValues={['true', 'false']} propertyValue={value as string} />
      )
    case 'string':
      return <StringPropertyInput {...props} propertyValue={value as string} />
    default:
      return null
  }
}

interface StringInputProps extends CustomPropertyInputProps {
  propertyValue: string
}

function StringPropertyInput({
  propertyValue,
  defaultValue,
  propertyName,
  mixed,
  onChange,
  hideDefaultPlaceholder,
  inputProps,
}: StringInputProps) {
  const placeholder = mixed ? mixedValuePlaceholder : hideDefaultPlaceholder ? '' : (defaultValue as string) || ''
  return (
    <TextInput
      block
      aria-label={propertyName}
      onChange={event => onChange(event.target.value)}
      value={propertyValue}
      placeholder={placeholder}
      {...inputProps}
    />
  )
}
