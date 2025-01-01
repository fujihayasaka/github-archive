import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import type React from 'react'
import {Link, NavLink} from 'react-router-dom'

import {jsonRoute} from '../JsonRoute'
import {Link as LinkToTest, NavLink as NavLinkToTest} from '../Link'
import {PREVENT_AUTOFOCUS_KEY} from '../prevent-autofocus'
import {RoutesContext} from '../routes-context'
import {render} from '../test-utils/Render'

vi.mock('react-router-dom', async () => {
  const originalModule = await vi.importActual('react-router-dom')
  return {
    ...originalModule,
    Link: vi.fn(() => null),
    NavLink: vi.fn(() => null),
  }
})

const Wrapper: React.FC<{children: React.ReactNode}> = ({children}) => {
  return (
    <RoutesContext.Provider
      value={{
        routes: [jsonRoute({path: '/a', Component: () => null})],
      }}
    >
      {children}
    </RoutesContext.Provider>
  )
}

beforeEach(() => {
  vi.clearAllMocks()
})

describe('Link', () => {
  it('renders without reloadDocument when linking within the app', () => {
    render(<LinkToTest to="/a" />, {wrapper: Wrapper})
    expect(Link).toHaveBeenCalledWith(expect.objectContaining({to: '/a', reloadDocument: false}), expect.anything())
  })

  it('renders with reloadDocument when linking outside of the app', () => {
    render(<LinkToTest to="/b" />, {wrapper: Wrapper})
    expect(Link).toHaveBeenCalledWith(expect.objectContaining({to: '/b', reloadDocument: true}), expect.anything())
  })

  it('handles preventAutofocus', () => {
    render(<LinkToTest to="/b" preventAutofocus />, {wrapper: Wrapper})
    expect(Link).toHaveBeenCalledWith(
      expect.objectContaining({to: '/b', reloadDocument: true, state: {[PREVENT_AUTOFOCUS_KEY]: true}}),
      expect.anything(),
    )
  })
})

describe('NavLink', () => {
  it('renders without reloadDocument when linking within the app', () => {
    render(<NavLinkToTest to="/a" />, {wrapper: Wrapper})
    expect(NavLink).toHaveBeenCalledWith(expect.objectContaining({to: '/a', reloadDocument: false}), expect.anything())
  })

  it('renders with reloadDocument when linking outside of the app', () => {
    render(<NavLinkToTest to="/b" />, {wrapper: Wrapper})
    expect(NavLink).toHaveBeenCalledWith(expect.objectContaining({to: '/b', reloadDocument: true}), expect.anything())
  })

  it('handles preventAutofocus', () => {
    render(<NavLinkToTest to="/b" preventAutofocus />, {wrapper: Wrapper})
    expect(NavLink).toHaveBeenCalledWith(
      expect.objectContaining({to: '/b', reloadDocument: true, state: {[PREVENT_AUTOFOCUS_KEY]: true}}),
      expect.anything(),
    )
  })
})
