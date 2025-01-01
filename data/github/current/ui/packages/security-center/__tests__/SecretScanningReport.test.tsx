import type {FilterProvider} from '@github-ui/filter'
import {render} from '@github-ui/react-core/test-utils'
import {act, renderHook, screen, waitFor} from '@testing-library/react'
import {useParams} from 'react-router-dom'

import {EnterprisePaths, OrgPaths} from '../common/contexts/Paths'
import type {CustomProperty} from '../common/filter-providers/types'
import {SecretScanningReport, useFilterProviders} from '../routes/SecretScanningReport'
import {getSecretScanningReportRoutePayload} from '../test-utils/mock-data'
import {PathsProvider} from '../test-utils/PathsProvider'

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: jest.fn(),
}))

describe('SecretScanningReport', () => {
  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation((message: string) => {
      // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
      // * any errors that are not related to the async nature of the component.
      if (!message.includes?.('wrapped in act(')) {
        // eslint-disable-next-line no-console
        console.error(message)
      }
    })
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })
  describe('at organization scope', () => {
    it('renders the view', () => {
      jest.mocked(useParams).mockImplementation(() => ({org: 'my-org'}))
      const routePayload = getSecretScanningReportRoutePayload()

      render(<SecretScanningReport />, {routePayload})

      expect(screen.getAllByRole('heading')?.[0]).toHaveTextContent('Secret scanning')
    })

    describe('useFilterProviders', () => {
      it('should include expected filter providers', async () => {
        const paths = new OrgPaths('my-org')
        let providers: FilterProvider[] | null = null

        renderHook(
          () =>
            act(() => {
              providers = useFilterProviders(paths, [])
            }),
          {wrapper: PathsProvider},
        )

        await waitFor(() =>
          expect(providers?.map(p => p.key)).toStrictEqual([
            'archived',
            'visibility',
            'repo',
            'team',
            'topic',
            'secret-type',
            'provider',
            'validity',
          ]),
        )
      })

      it('should include alert specific filters if feature enabled', async () => {
        const paths = new OrgPaths('my-org')
        let providers: FilterProvider[] | null = null

        renderHook(
          () =>
            act(() => {
              providers = useFilterProviders(paths, [])
            }),
          {wrapper: PathsProvider},
        )

        await waitFor(() =>
          expect(providers?.map(p => p.key)).toStrictEqual([
            'archived',
            'visibility',
            'repo',
            'team',
            'topic',
            'secret-type',
            'provider',
            'validity',
          ]),
        )
      })

      it('should include providers for repository custom properties', async () => {
        const paths = new OrgPaths('my-org')
        const customProperties: CustomProperty[] = [
          {name: 'foo', type: 'string'},
          {name: 'bar', type: 'single_select'},
          {name: 'baz', type: 'multi_select'},
          {name: 'qux', type: 'true_false'},
        ]
        let providers: FilterProvider[] | null = null

        renderHook(
          () =>
            act(() => {
              providers = useFilterProviders(paths, customProperties)
            }),
          {wrapper: PathsProvider},
        )

        await waitFor(() =>
          expect(providers?.map(p => p.key)).toStrictEqual([
            'archived',
            'visibility',
            'repo',
            'team',
            'topic',
            'secret-type',
            'provider',
            'validity',
            'props.foo',
            'props.bar',
            'props.baz',
            'props.qux',
          ]),
        )
      })
    })
  })

  describe('at enterprise scope', () => {
    it('renders the view', () => {
      jest.mocked(useParams).mockImplementation(() => ({business: 'my-biz'}))
      const routePayload = getSecretScanningReportRoutePayload()

      render(<SecretScanningReport />, {routePayload})

      expect(screen.getAllByRole('heading')?.[0]).toHaveTextContent('Secret scanning')
    })

    describe('useFilterProviders', () => {
      it('should include expected filter providers', async () => {
        const paths = new EnterprisePaths('my-biz')
        let providers: FilterProvider[] | null = null

        renderHook(
          () =>
            act(() => {
              providers = useFilterProviders(paths, [])
            }),
          {wrapper: PathsProvider},
        )

        await waitFor(() =>
          expect(providers?.map(p => p.key)).toStrictEqual([
            'archived',
            'visibility',
            'repo',
            'team',
            'topic',
            'secret-type',
            'provider',
            'validity',
            'owner',
          ]),
        )
      })

      it('should include owner-type filter if feature enabled', async () => {
        const paths = new EnterprisePaths('my-biz')
        let providers: FilterProvider[] | null = null

        renderHook(
          () =>
            act(() => {
              providers = useFilterProviders(paths, [], true)
            }),
          {wrapper: PathsProvider},
        )

        await waitFor(() =>
          expect(providers?.map(p => p.key)).toStrictEqual([
            'archived',
            'visibility',
            'repo',
            'team',
            'topic',
            'secret-type',
            'provider',
            'validity',
            'owner',
            'owner-type',
          ]),
        )
      })
    })
  })
})
