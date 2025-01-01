import {describe, expect, it} from '@github-ui/tests'

import type {EmbeddedData} from '../../embedded-data-types'
import {DataRouterApplicationBuilder, type GetRoutesFunction} from '../../future/data-router-application'

describe('DataRouterApplication', () => {
  describe('registration', () => {
    function buildEmbeddedDataWithFeatures(features: Record<string, boolean>): EmbeddedData {
      return {
        appPayload: {enabled_features: features},
        payload: {},
      }
    }

    it('returns routes defined statically', () => {
      const builder = DataRouterApplicationBuilder.create('react-core')
      const pageId = builder.createQueryRouteConfig('pageId', {
        path: '/page/:id',
        queries: [],
      })

      const application = builder.createDataRouterAppFromRoutes([pageId])
      const registration = application.registration()

      expect(registration.routes).toEqual([pageId])
    })

    it('returns routes defined via function', () => {
      const builder = DataRouterApplicationBuilder.create('react-core')
      const pageId = builder.createQueryRouteConfig('pageId', {
        path: '/page/:id',
        queries: [],
      })

      const application = builder.createDataRouterAppFromRoutes(() => [pageId])
      const registration = application.registration()

      expect(registration.routes).toEqual([pageId])
    })

    it('handles feature flag not found in embedded data', () => {
      const builder = DataRouterApplicationBuilder.create('react-core')
      const pageId1 = builder.createQueryRouteConfig('pageId1', {
        path: '/page/:id',
        queries: [],
      })

      const pageId2 = builder.createQueryRouteConfig('pageId2', {
        path: '/page/:id',
        queries: [],
      })

      const getRoutes: GetRoutesFunction = ({isEnabled}) => (isEnabled('featureName') ? [pageId1] : [pageId2])

      const application = builder.createDataRouterAppFromRoutes(getRoutes)
      const registration = application.registration()

      expect(registration.routes).toEqual([pageId2])
    })

    it('checks FF value in embedded data', () => {
      const builder = DataRouterApplicationBuilder.create('react-core')
      const pageId1 = builder.createQueryRouteConfig('pageId1', {
        path: '/page/:id',
        queries: [],
      })

      const pageId2 = builder.createQueryRouteConfig('pageId2', {
        path: '/page/:id',
        queries: [],
      })

      const getRoutes: GetRoutesFunction = ({isEnabled}) => (isEnabled('featureName') ? [pageId1] : [pageId2])

      const application = builder.createDataRouterAppFromRoutes(getRoutes)

      const registrationWithFeatureDisabled = application.registration({
        embeddedData: buildEmbeddedDataWithFeatures({featureName: false}),
      })
      expect(registrationWithFeatureDisabled.routes).toEqual([pageId2])

      const registrationWithFeatureEnabled = application.registration({
        embeddedData: buildEmbeddedDataWithFeatures({featureName: true}),
      })
      expect(registrationWithFeatureEnabled.routes).toEqual([pageId1])
    })
  })
})
