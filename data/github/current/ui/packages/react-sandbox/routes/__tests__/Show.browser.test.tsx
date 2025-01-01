import {jsonRoute} from '@github-ui/react-core/json-route'
import {render, RouteContext} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {screen} from '@testing-library/react'
import {Route, Routes} from 'react-router-dom'

import {SandboxLayout} from '../../SandboxLayout'
import {ShowPage} from '../Show'

it('Renders the show page at the URL', async () => {
  const {user} = render(
    <Routes>
      <Route path="/_react_sandbox/:sandbox_id" element={<ShowPage />} />
    </Routes>,
    {
      routePayload: 'payload',
      pathname: '/_react_sandbox/123',
      routes: [
        jsonRoute({
          path: '/_react_sandbox/:sandbox_id',
          Component: () => null,
        }),
      ],
      wrapper: SandboxLayout,
    },
  )

  expect(RouteContext.location?.pathname).toBe('/_react_sandbox/123')
  expect(screen.getByRole('heading')).toHaveTextContent('React sandbox show page (sandbox ID: 123)')

  // eslint-disable-next-line testing-library/no-node-access,
  await user.click(screen.getByText('Show 1').closest('a')!)

  expect(RouteContext.location?.pathname).toBe('/_react_sandbox/1')
  expect(screen.getByRole('heading')).toHaveTextContent('React sandbox show page (sandbox ID: 1)')
})
