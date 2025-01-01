import type {ValueType} from '@github-ui/custom-properties-types'
import {getEmptyValueByType} from '@github-ui/custom-properties-types/helpers'
import {TextInput} from '@primer/react'
import {forwardRef, type HTMLAttributes} from 'react'

import {CustomPropertyBooleanSelectPanel} from './controls/CustomPropertyBooleanSelectPanel'
import {CustomPropertyMultiSelectPanel} from './controls/CustomPropertyMultiSelectPanel'
import {CustomPropertySingleSelectPanel} from './controls/CustomPropertySingleSelectPanel'
import {CustomPropertyStringEditor} from './controls/CustomPropertyStringEditor'
import type {CustomPropertySelectPanelProps} from './CustomPropertySelectPanel'
import {
  CustomPropertyMultiSelectPanel as OldCustomPropertyMultiSelectPanel,
  CustomPropertySingleSelectPanel as OldCustomPropertySingleSelectPanel,
  mixedValuePlaceholder,
} from './CustomPropertySelectPanel'

interface CustomPropertyInputProps extends CustomPropertySelectPanelProps {
  valueType: ValueType
  orgName: string
  editingRedesignEnabled?: boolean
  regex?: string | null
  inputProps?: HTMLAttributes<HTMLInputElement>
}

export const CustomPropertyInput = forwardRef(
  (props: CustomPropertyInputProps, ref: React.ForwardedRef<HTMLElement>) => {
    const {valueType, defaultValue, regex, mixed, onChange, orgName, editingRedesignEnabled} = props
    const value = props.propertyValue || getEmptyValueByType(valueType)

    if (editingRedesignEnabled) {
      switch (valueType) {
        case 'single_select':
          return <CustomPropertySingleSelectPanel {...props} propertyValue={value as string} />
        case 'multi_select':
          return <CustomPropertyMultiSelectPanel {...props} propertyValue={value as string[]} />
        case 'true_false':
          return <CustomPropertyBooleanSelectPanel {...props} propertyValue={value as string} />
        case 'string':
          return (
            <CustomPropertyStringEditor
              propertyValue={value as string}
              defaultValue={defaultValue as string}
              regexPattern={regex}
              mixed={mixed}
              orgName={orgName}
              onChange={onChange}
            />
          )
        default:
          return null
      }
    }

    switch (valueType) {
      case 'single_select':
        return <OldCustomPropertySingleSelectPanel {...props} propertyValue={value as string} />
      case 'multi_select':
        return <OldCustomPropertyMultiSelectPanel {...props} propertyValue={value as string[]} />
      case 'true_false':
        return (
          <OldCustomPropertySingleSelectPanel
            {...props}
            allowedValues={['true', 'false']}
            propertyValue={value as string}
          />
        )
      case 'string':
        return <StringPropertyInput ref={ref} {...props} propertyValue={value as string} />

      default:
        return null
    }
  },
)
CustomPropertyInput.displayName = 'CustomPropertyInput'

interface StringInputProps extends CustomPropertyInputProps {
  propertyValue: string
}

export const StringPropertyInput = forwardRef(
  (
    {propertyValue, defaultValue, propertyName, mixed, onChange, inputProps}: StringInputProps,
    ref: React.ForwardedRef<HTMLElement>,
  ) => {
    const placeholder = mixed ? mixedValuePlaceholder : (defaultValue as string) || ''
    return (
      <TextInput
        ref={ref as React.ForwardedRef<HTMLInputElement>}
        block
        aria-label={propertyName}
        onChange={event => onChange(event.target.value)}
        value={propertyValue}
        placeholder={placeholder}
        {...inputProps}
      />
    )
  },
)
StringPropertyInput.displayName = 'StringPropertyInput'
