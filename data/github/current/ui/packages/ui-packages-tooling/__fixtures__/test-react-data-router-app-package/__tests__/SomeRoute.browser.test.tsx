import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {it, expect, describe, beforeEach, afterEach} from '@github-ui/tests'
import {msw} from '@github-ui/tests/msw'
import {getSomeRouteRoutePayload} from './utils/mock-data'
import {testReactDataRouterAppPackageApp} from '../test-react-data-router-app-package'
import {handlers} from './utils/handlers'

describe('test-react-data-router-app-package', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })
  afterEach(() => {
    msw.resetHandlers()
  })
  it('Renders the SomeRoute component', async () => {
    render(testReactDataRouterAppPackageApp, '/some/:id/route', {
      appPayload: {},
    })

    expect(await screen.findByText('SomeRoute for test-react-data-router-app-package')).toBeInTheDocument()
  })

  it('Renders the SomeRoute component with embedded data', async () => {
    const mainQuery = getSomeRouteRoutePayload()

    render(testReactDataRouterAppPackageApp, '/some/:id/route', {
      embeddedData: {
        payload: {
          someRouteRoute: mainQuery,
        },
      },
    })

    expect(await screen.findByText('someValue')).toBeInTheDocument()
  })
})
