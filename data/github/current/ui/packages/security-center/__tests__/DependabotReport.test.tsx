import type {FilterProvider} from '@github-ui/filter'
import {render} from '@github-ui/react-core/test-utils'
import {act, renderHook, screen, waitFor} from '@testing-library/react'
import {useParams} from 'react-router-dom'

import {OrgPaths} from '../common/contexts/Paths'
import type {CustomProperty} from '../common/filter-providers/types'
import {getSecurityCenterDependabotMetricsProps} from '../dependabot-report/test-utils/mock-data'
import {DependabotReport, useFilterProviders} from '../routes/DependabotReport'
import {PathsProvider} from '../test-utils/PathsProvider'

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: jest.fn(),
}))

describe('DependabotReport', () => {
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
      const routePayload = getSecurityCenterDependabotMetricsProps()

      render(<DependabotReport />, {routePayload})

      expect(screen.getAllByRole('heading')?.[0]).toHaveTextContent('Dependabot')
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
            'repo',
            'topic',
            'team',
            'visibility',
            'archived',
            'state',
            'severity',
            'scope',
            'package',
            'ecosystem',
            'relationship',
            'epss_percentage',
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
            'repo',
            'topic',
            'team',
            'visibility',
            'archived',
            'state',
            'severity',
            'scope',
            'package',
            'ecosystem',
            'relationship',
            'epss_percentage',
            'props.foo',
            'props.bar',
            'props.baz',
            'props.qux',
          ]),
        )
      })
    })
  })

  // TODO : Add tests for the enterprise scope for Dependabot is not available for enterprise scope
})
