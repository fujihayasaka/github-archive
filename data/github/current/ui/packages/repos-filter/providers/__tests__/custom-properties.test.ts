import {FilterProviderType} from '@github-ui/filter'

import {getCustomPropertiesProvider, type PropertyDefinition} from '../custom-properties'

const sampleDefinitions: PropertyDefinition[] = [
  {
    propertyName: 'env',
    allowedValues: ['dev', 'prod', 'test'],
    valueType: 'single_select',
    required: true,
  },
  {
    propertyName: 'owner',
    valueType: 'string',
  },
  {
    propertyName: 'yesno',
    valueType: 'true_false',
  },
  {
    propertyName: 'platform',
    valueType: 'multi_select',
    allowedValues: ['android', 'ios', 'web'],
  },
]

describe('getCustomPropertiesProvider', () => {
  test('creates one provider with nested keys per definition', () => {
    const provider = getCustomPropertiesProvider(sampleDefinitions)

    expect(provider.filterProviders).toHaveLength(4 + 1)

    expect(provider.filterProviders[4]!.displayName).toEqual('Custom properties')

    const selectProvider = provider.filterProviders[0]!
    expect(selectProvider.displayName).toEqual('Property: env')
    expect(selectProvider.key).toEqual('props.env')
    expect(selectProvider.type).toBe(FilterProviderType.Select)
    expect(selectProvider.filterValues!.map(item => item.value)).toEqual(['dev', 'prod', 'test'])

    const textProvider = provider.filterProviders[1]!
    expect(textProvider.displayName).toEqual('Property: owner')
    expect(textProvider.key).toEqual('props.owner')
    expect(textProvider.type).toBe(FilterProviderType.Text)
    expect(textProvider.filterValues).toBeUndefined()

    const boolProvider = provider.filterProviders[2]!
    expect(boolProvider.displayName).toEqual('Property: yesno')
    expect(boolProvider.key).toEqual('props.yesno')
    expect(boolProvider.type).toBe(FilterProviderType.Select)
    expect(boolProvider.filterValues!.map(item => item.value)).toEqual(['true', 'false'])

    const multiSelectProvider = provider.filterProviders[3]!
    expect(multiSelectProvider.displayName).toEqual('Property: platform')
    expect(multiSelectProvider.key).toEqual('props.platform')
    expect(multiSelectProvider.type).toBe(FilterProviderType.Select)
    expect(multiSelectProvider.filterValues!.map(item => item.value)).toEqual(['android', 'ios', 'web'])
  })

  test('shows no: qualifier only for non-required properties', () => {
    const provider = getCustomPropertiesProvider(sampleDefinitions)

    const selectProvider = provider.filterProviders[0]!
    expect(selectProvider.options.filterTypes.valueless).toBeFalsy()

    const textProvider = provider.filterProviders[1]!
    expect(textProvider.options.filterTypes.valueless).toBeTruthy()

    const boolProvider = provider.filterProviders[2]!
    expect(boolProvider.options.filterTypes.valueless).toBeTruthy()

    const multiSelectProvider = provider.filterProviders[3]!
    expect(multiSelectProvider.options.filterTypes.valueless).toBeTruthy()
  })

  test('valueless option applies only to non-required property', () => {
    const provider = getCustomPropertiesProvider(
      [
        {propertyName: 'optional', valueType: 'string'},
        {propertyName: 'required', valueType: 'string', required: true},
      ],
      {valueless: true},
    )

    expect(provider.filterProviders).toHaveLength(2 + 1)

    const optional = provider.filterProviders[0]!
    expect(optional.displayName).toEqual('Property: optional')
    expect(optional.options.filterTypes.valueless).toBeTruthy()

    const required = provider.filterProviders[1]!
    expect(required.displayName).toEqual('Property: required')
    expect(required.options.filterTypes.valueless).toBeFalsy()
  })
})
