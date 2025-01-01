import '../ReactAppElement'

import {CatalystDelegate} from '@github/catalyst/lib/core'
import {describe, expect, it, vi} from '@github-ui/tests'
import {render, screen} from '@testing-library/react'

import {DataRouterApplicationBuilder} from '../future/data-router-application'
import {useIsDataRouterEnabled} from '../future/use-is-data-router-enabled'
import {jsonRoute} from '../JsonRoute'
import {registerDataRouterApp, registerNavigatorApp} from '../register-app'

/**
 * This gets scheduled in catalyst for after the test is completed. So we're mocking it to avoid
 * console.log noise
 */
vi.spyOn(CatalystDelegate.prototype, 'disconnectedCallback').mockImplementation(() => {})

function Page() {
  const isDataRouterEnabled = useIsDataRouterEnabled()
  return <p>{isDataRouterEnabled ? 'Data router app' : 'Navigator router app'}</p>
}
registerDataRouterApp(
  DataRouterApplicationBuilder.create('react-core').createDataRouterAppFromRoutes([
    {
      path: '*',
      Component: Page,
    },
  ]),
)

registerNavigatorApp('react-core', () => {
  return {
    routes: [
      jsonRoute({
        path: '*',
        Component: Page,
      }),
    ],
  }
})

describe('ReactAppElement', () => {
  it('renders data router', async () => {
    renderReactElement({dataRouterEnabled: true})
    expect(await screen.findByText('Data router app')).toBeInTheDocument()
    expect(screen.getByTestId('react-app')).toHaveAttribute('data-data-router-enabled', 'true')
  })

  it('renders navigator app', async () => {
    renderReactElement({dataRouterEnabled: false})
    expect(await screen.findByText('Navigator router app')).toBeInTheDocument()
    expect(screen.getByTestId('react-app')).toHaveAttribute('data-data-router-enabled', 'false')
  })

  it('renders navigator app if not attribute at all', async () => {
    renderReactElement({})
    expect(await screen.findByText('Navigator router app')).toBeInTheDocument()
    expect(screen.getByTestId('react-app')).not.toHaveAttribute('data-data-router-enabled')
  })
})

interface RenderReactElementOptions {
  dataRouterEnabled?: boolean
}

function renderReactElement({dataRouterEnabled}: RenderReactElementOptions) {
  return render(
    <react-app
      app-name="react-core"
      initial-path="/"
      data-ssr="false"
      data-testid="react-app"
      {...(typeof dataRouterEnabled === 'boolean' ? {['data-data-router-enabled']: `${dataRouterEnabled}`} : {})}
    >
      <script type="application/json" data-target="react-app.embeddedData">
        {JSON.stringify({})}
      </script>
      <div data-target="react-app.reactRoot" />
    </react-app>,
  )
}
