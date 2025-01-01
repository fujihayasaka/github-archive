// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook} from '@testing-library/react'

import {businessCustomPropertiesRoute, definitionsRoute} from '../../custom-properties'
import {albumDefinition, sampleBusinessSource} from '../../test-utils/mock-data'
import {getRouteWrapper} from '../../test-utils/RouteWrapper'
import {useEditPropertyPath, useEditPropertyPathBuilder, useNewPropertyPath} from '../use-property-details-paths'

describe('useNewPropertyPath', () => {
  it('returns path from organization route', () => {
    const {result} = renderHook(() => useNewPropertyPath(), {
      wrapper: getRouteWrapper('/organizations/acme/settings/custom-properties', definitionsRoute),
    })

    expect(result.current).toEqual('/organizations/acme/settings/custom-property')
  })

  it('returns path from enterprise route', () => {
    const {result} = renderHook(() => useNewPropertyPath(), {
      wrapper: getRouteWrapper('/enterprises/acme-corp/settings/custom-properties', businessCustomPropertiesRoute),
    })

    expect(result.current).toEqual('/enterprises/acme-corp/settings/custom-property')
  })
})

describe('useEditPropertyPath', () => {
  it('returns path from organization route', () => {
    const {result} = renderHook(() => useEditPropertyPath(albumDefinition), {
      wrapper: getRouteWrapper('/organizations/acme/settings/custom-properties', definitionsRoute),
    })

    expect(result.current).toEqual(`/organizations/acme/settings/custom-property/${albumDefinition.propertyName}`)
  })

  it('returns path from enterprise route', () => {
    const businessSourceDefinition = {
      ...albumDefinition,
      source: sampleBusinessSource,
    }
    const {result} = renderHook(() => useEditPropertyPath(businessSourceDefinition), {
      wrapper: getRouteWrapper('/enterprises/acme-corp/settings/custom-properties', businessCustomPropertiesRoute),
    })

    expect(result.current).toEqual(
      `/enterprises/acme-corp/settings/custom-property/${businessSourceDefinition.propertyName}`,
    )
  })

  it('returns enterprise org path from enterprise route with org source details payload', () => {
    const {result} = renderHook(() => useEditPropertyPath(albumDefinition), {
      wrapper: getRouteWrapper('/enterprises/acme-corp/settings/custom-properties', businessCustomPropertiesRoute),
    })

    expect(result.current).toEqual(
      `/enterprises/acme-corp/settings/custom-property/organizations/github/${albumDefinition.propertyName}`,
    )
  })
})

describe('useEditPropertyPathBuilder', () => {
  it('returns path from organization route', () => {
    const {result} = renderHook(useEditPropertyPathBuilder, {
      wrapper: getRouteWrapper('/organizations/acme/settings/custom-properties', definitionsRoute),
    })

    expect(result.current('environment')).toEqual('/organizations/acme/settings/custom-property/environment')
  })

  it('returns path from enterprise route', () => {
    const {result} = renderHook(useEditPropertyPathBuilder, {
      wrapper: getRouteWrapper('/enterprises/acme-corp/settings/custom-properties', businessCustomPropertiesRoute),
    })

    expect(result.current('environment')).toEqual('/enterprises/acme-corp/settings/custom-property/environment')
  })
})
