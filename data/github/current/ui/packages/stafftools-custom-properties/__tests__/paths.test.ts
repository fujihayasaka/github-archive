import {
  businessCustomPropertyDefinitionStafftoolsDetailsPath,
  businessCustomPropertyDefinitionStafftoolsListPath,
  orgCustomPropertiesDefinitionStafftoolsListPath,
  orgCustomPropertyDefinitionStafftoolsDetailsPath,
} from '../paths'

describe('orgCustomPropertyDefinitionStafftoolsDetailsPath', () => {
  test('returns correct path', async () => {
    expect(
      orgCustomPropertyDefinitionStafftoolsDetailsPath({
        org: 'acme',
        propertyName: 'feature',
      }),
    ).toEqual('/stafftools/users/acme/organization_custom_properties/feature')
  })

  test('encodes special characters', async () => {
    expect(
      orgCustomPropertyDefinitionStafftoolsDetailsPath({
        org: '你好',
        propertyName: 'C#/lib',
      }),
    ).toEqual('/stafftools/users/%E4%BD%A0%E5%A5%BD/organization_custom_properties/C%23%2Flib')
  })
})

describe('orgCustomPropertiesDefinitionStafftoolsListPath', () => {
  test('returns correct path', async () => {
    expect(
      orgCustomPropertiesDefinitionStafftoolsListPath({
        org: 'acme',
      }),
    ).toEqual('/stafftools/users/acme/organization_custom_properties')
  })

  test('encodes special characters', async () => {
    expect(
      orgCustomPropertiesDefinitionStafftoolsListPath({
        org: '你好',
      }),
    ).toEqual('/stafftools/users/%E4%BD%A0%E5%A5%BD/organization_custom_properties')
  })
})

describe('businessCustomPropertyDefinitionStafftoolsDetailsPath', () => {
  test('returns correct path', async () => {
    expect(
      businessCustomPropertyDefinitionStafftoolsDetailsPath({
        enterprise: 'acme-corp',
        propertyName: 'feature',
      }),
    ).toEqual('/stafftools/enterprises/acme-corp/custom_properties/feature')
  })

  test('encodes special characters', async () => {
    expect(
      businessCustomPropertyDefinitionStafftoolsDetailsPath({
        enterprise: '你好-corp',
        propertyName: 'C#/lib',
      }),
    ).toEqual('/stafftools/enterprises/%E4%BD%A0%E5%A5%BD-corp/custom_properties/C%23%2Flib')
  })
})

describe('businessCustomPropertyDefinitionStafftoolsListPath', () => {
  test('returns correct path', async () => {
    expect(
      businessCustomPropertyDefinitionStafftoolsListPath({
        enterprise: 'acme-corp',
      }),
    ).toEqual('/stafftools/enterprises/acme-corp/custom_properties')
  })

  test('encodes special characters', async () => {
    expect(
      businessCustomPropertyDefinitionStafftoolsListPath({
        enterprise: '你好-corp',
      }),
    ).toEqual('/stafftools/enterprises/%E4%BD%A0%E5%A5%BD-corp/custom_properties')
  })
})
