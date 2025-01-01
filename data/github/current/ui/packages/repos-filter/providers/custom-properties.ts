import type {ValueType} from '@github-ui/custom-properties-types'
import type {FilterProviderOptions} from '@github-ui/filter'
import {defaultFilterProviderOptions, TRUE_FALSE_FILTER_VALUES} from '@github-ui/filter'
import {NestedFilterProvider} from '@github-ui/filter/providers'
import {NoteIcon} from '@primer/octicons-react'

export interface PropertyDefinition {
  propertyName: string
  allowedValues?: string[] | null
  required?: boolean
  valueType: ValueType
}

interface CustomPropertiesFilterOptions {
  /**
   * Whether `no:` qualifier is supported.
   * Takes effect only for non-required properties.
   * Defaults to true.
   **/
  valueless?: boolean
  /**
   * Whether the same property name is suggested multiple times.
   * Multiple keys in the query describe an `AND` condition.
   * Takes effect only for properties of type `multi_select`.
   * Defaults to true.
   **/
  // Remove the multiKey param when the feature flag ruleset_allow_dup_multi_select_props is removed
  multiKey?: boolean
}

export function getCustomPropertiesProvider(
  definitions: PropertyDefinition[],
  options: Partial<CustomPropertiesFilterOptions> = {},
) {
  return new NestedFilterProvider({
    key: 'props',
    displayName: 'Custom properties',
    description: 'Filter by custom properties',
    priority: 3,
    icon: NoteIcon,
    subKeys: definitions.map(d => buildSubKey(d, options)),
  })
}

type SubKeyType = 'select' | 'text'

function buildSubKey(definition: PropertyDefinition, options: Partial<CustomPropertiesFilterOptions>) {
  const {propertyName, valueType} = definition
  const values =
    valueType === 'true_false'
      ? TRUE_FALSE_FILTER_VALUES
      : (definition.allowedValues || []).map((value, index) => ({value, displayName: value, priority: index + 1}))

  return {
    key: propertyName,
    displayName: `Property: ${propertyName}`,
    icon: NoteIcon,
    type: (valueType === 'string' ? 'text' : 'select') as SubKeyType,
    values,
    options: getFilterOptions(definition, options),
  }
}

function getFilterOptions(
  {valueType, required}: PropertyDefinition,
  options: Partial<CustomPropertiesFilterOptions>,
): FilterProviderOptions {
  return {
    ...defaultFilterProviderOptions,
    filterTypes: {
      multiKey: valueType === 'multi_select' ? options.multiKey ?? true : false,
      multiValue: true,
      valueless: required ? false : options.valueless ?? true,
    },
  }
}

export function isCustomPropertiesKey(key: string) {
  const lowerKey = key.toLowerCase()
  return lowerKey.startsWith('properties.') || lowerKey.startsWith('props.') || lowerKey.startsWith('p.')
}
