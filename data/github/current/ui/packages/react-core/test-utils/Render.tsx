import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {ToastContextProvider} from '@github-ui/toast/ToastContext'
import {ThemeProvider} from '@primer/react'
import type {StoryContext, StoryFn} from '@storybook/react'
import {QueryClientProvider} from '@tanstack/react-query'
import {
  render as rtlRender,
  renderHook as rtlRenderHook,
  type RenderHookOptions,
  type RenderHookResult,
  type RenderOptions,
  type RenderResult as CoreRenderResult,
} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import type {Options as ImportedUserEventOptions, UserEvent} from '@testing-library/user-event'
// eslint-disable-next-line no-restricted-imports
import {userEvent} from '@testing-library/user-event'
import {type FC, type ReactElement, type ReactNode, useEffect, useMemo} from 'react'
import {type Location, MemoryRouter, useLocation} from 'react-router-dom'

import {BaseProviders} from '../BaseProviders'
import {CommonElements} from '../CommonElements'
import {jsonRoute} from '../JsonRoute'
import type {NavigatorAppRegistration} from '../navigator-app-registry'
import {getQueryClient} from '../query-client'
import {RouteStateMapContext} from '../route-state-map-context'
import {RoutesContextProvider} from '../RoutesContextProvider'
import {AppPayloadContext} from '../use-app-payload'

export type UserEventOptions = ImportedUserEventOptions

const isJestEnvironment = () => typeof jest !== 'undefined'

interface WrapperProps {
  appName?: string
  pathname?: string
  pathPattern?: string
  // If defined, search should be a string that starts with `?`
  search?: string
  // If defined, hash should be a string that starts with `#`
  hash?: string
  routePayload?: unknown
  appPayload?: unknown
  /**
   * Determines the AppContext value, which drives behaviors around things like links.
   */
  routes?: NavigatorAppRegistration['routes']
  children?: ReactNode
}

export const Wrapper: FC<WrapperProps> = ({
  appName = 'test-app',
  children,
  pathname = '/',
  pathPattern = pathname,
  search = undefined,
  hash = undefined,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  routePayload = {},
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  appPayload = {},
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  routes = [jsonRoute({path: pathPattern, Component: () => null})],
}) => {
  const key = 'k1'
  // @ts-expect-error `routePayload` types don't account for title properties directly
  const title = (routePayload && routePayload['title']) || 'Test title'
  return (
    <QueryClientProvider client={getQueryClient()}>
      <RoutesContextProvider routes={routes}>
        <ThemeProvider>
          <AnalyticsProvider appName={appName} category="" metadata={{}}>
            <MemoryRouter
              initialEntries={[{pathname, search, hash, key}]}
              future={{v7_relativeSplatPath: true, v7_startTransition: true}}
            >
              <AppPayloadContext.Provider value={appPayload}>
                <ToastContextProvider>
                  <RouteStateMapContext.Provider
                    value={useMemo(
                      () => ({
                        [key]: {
                          type: 'loaded',
                          data: {payload: routePayload},
                          title,
                        },
                      }),
                      [routePayload, title],
                    )}
                  >
                    <>{children}</>
                    <RouteContext />
                  </RouteStateMapContext.Provider>
                  <CommonElements />
                </ToastContextProvider>
              </AppPayloadContext.Provider>
            </MemoryRouter>
          </AnalyticsProvider>
        </ThemeProvider>
      </RoutesContextProvider>
    </QueryClientProvider>
  )
}

type RouteContextType = {
  (): null
  location: Location | null
}
export const RouteContext: RouteContextType = () => {
  const location = useLocation()
  useEffect(() => {
    RouteContext.location = location
  })
  return null
}
/**
 * `RouteContext.location` provides access to the current `location` context provided by the `MemoryRouter`
 * rendered in `Wrapper` via `render()`. This location can be used in tests to assert on the current location or wait for a route change.
 *
 * @see https://github.com/remix-run/react-router/blob/main/packages/react-router/__tests__/Router-test.tsx#L28-L32
 * @see https://github.com/github/github/blob/master/ui/packages/react-sandbox/routes/__tests__/Show.test.tsx
 *
 * @example
 * ```ts
 * import {screen, fireEvent} from "@testing-library/react"
 * import {render, RouteContext} from 'react-core/test-utils'
 *
 * test('navigates to /shawarma', () => {
 *   render(<MyComponent />, {pathname: '/falafel'})
 *   expect(RouteContext.location?.pathname).toBe('/falafel')
 *   fireEvent.click(screen.getByText('Shawarma'))
 *   expect(RouteContext.location?.pathname).toBe('/shawarma')
 * })
 * ```
 */
RouteContext.location = null

export type User = UserEvent & {
  /**
   * Clicking a link directly will log an error because page navigation is not supported by the testing library.
   * This alternative will prevent page navigation when clicking the link, allowing it to still emit click events.
   *
   * @note If a click event handler on the link checks for `event.defaultPrevented`, the handler behavior will be
   * affected because this method calls `preventDefault` on click.
   */
  clickLink(anchor: HTMLElement): Promise<void>
}

/**
 * Calls `userEvent.setup()` while adding the `clickLink` API and a fix for `useFakeTimer`.
 *
 * @warning Tests should typically not need to call this directly! If you are using the `render` function from this
 * package, you should simply unpack `user` from the result: `const {user} = render(...)`.
 */
export const setupUserEvent = (options?: ImportedUserEventOptions): User => {
  if (!userEvent) throw new Error('user-event requires a browser and cannot be accessed in an SSR context.')

  const userEventConfig = isJestEnvironment() ? getUserEventConfigForJest() : {}

  const coreUser = userEvent.setup({
    ...userEventConfig,
    ...options,
  })

  return {
    ...coreUser,
    clickLink: async (element: HTMLElement) => {
      const preventNavigation = (e: MouseEvent) => e.preventDefault()
      element.addEventListener('click', preventNavigation)
      await coreUser.click(element)
      element.removeEventListener('click', preventNavigation)
    },
  }
}

const getUserEventConfigForJest = () => {
  return {
    advanceTimers: (delay: number) => {
      // If fake timers are not enabled, a warning will be logged which will cause tests to fail. This warning is safe
      // to ignore in this case since we want it to work regardless of whether fake timers are enabled or not.

      // eslint-disable-next-line no-console
      const _warn = console.warn
      // eslint-disable-next-line no-console
      console.warn = jest.fn()
      jest.advanceTimersByTime(delay)
      // eslint-disable-next-line no-console
      console.warn = _warn
    },
  }
}

/**
 *
 * @param result An object that has all of the properties returned from testing-library/render
 * @param userEventOptions an optional object of config for `userEvent.setup()`
 * @returns the result with an additional `user` getter that
 */
export function withUserEvent<View extends ReturnType<typeof rtlRender>>(
  view: View & {user?: never},
  userEventOptions?: UserEventOptions,
): View & {readonly user: User} {
  /**
   *  `user` is lazily initiated to prevent unnecessary side effects since many tests don't use
   * userEvent or are still on v13
   *  */
  let user: User | undefined

  return Object.assign(view, {
    /**
     * @deprecated
     * If you're using vitest, you probably want to use `import {userEvent} from '@github-ui/tests/browser'` instead of
     * this user object. Vitest runs your user facing tests in a real browser so it doesn't need to simulate events
     *
     * If your tests are running in jsdom/jest, this is not deprecated.
     *
     * @see https://testing-library.com/docs/user-event/intro
     * @see https://vitest.dev/guide/browser/interactivity-api.html#interactivity-api
     */
    get user() {
      return (user ??= setupUserEvent(userEventOptions))
    },
  })
}

export type TestRenderOptions = RenderOptions &
  WrapperProps & {
    userEventOptions?: ImportedUserEventOptions
  }

export type RenderResult = CoreRenderResult & {
  /**
   * `userEvent` instance for testing user interactions. Using this instance is preferable over calling methods on
   * `userEvent` directly because it will automatically advance timers when using `jest.useFakeTimers()`, and will
   * automatically mock the clipboard state across a test.
   *
   * IMPORTANT: Note that this `user` is built with `user-event@14`
   */
  user: User
}

export const render = (
  ui: ReactElement,
  {
    pathname,
    pathPattern,
    routePayload,
    appPayload,
    search,
    hash,
    routes,
    wrapper: InnerWrapper,
    appName,
    userEventOptions,
    ...passthroughOptions
  }: TestRenderOptions = {},
): RenderResult => {
  const view = rtlRender(ui, {
    wrapper: ({children}) => (
      <Wrapper
        appName={appName}
        routePayload={routePayload}
        appPayload={appPayload}
        pathname={pathname}
        pathPattern={pathPattern}
        search={search}
        hash={hash}
        routes={routes}
      >
        {InnerWrapper ? <InnerWrapper>{children}</InnerWrapper> : children}
      </Wrapper>
    ),
    ...passthroughOptions,
  })

  return withUserEvent(view, userEventOptions)
}

/**
 * Returns a [storybook decorator](https://storybook.js.org/docs/writing-stories/decorators) that wraps the story in
 * the `react-core/test-utils`Wrapper`
 *
 * @example
 * ```tsx
 * import type {Meta} from '@storybook/react'
 * import {storyWrapper} from 'react-core/test-utils'
 *
 * // define the story Meta
 * export default {
 *  title: 'MyComponent',
 *  component: MyComponent,
 *  // wrap every story in the decorators defined on the Meta.
 *  decorators: [storyWrapper({pathname: '/falafel', appPayload: {owner: 'monalisa'}})],
 * } satisfies Meta<typeof MyComponent>
 *
 * // The story wrapper will wrap this story with the default props defined in the Meta
 * export const Example = {}
 *
 * // or you can override props on an individual story via parameters.storyWrapper
 * export const OtherExample = {parameters: {storyWrapper: {pathname: '/shawarma'}}}
 *
 * // or you can wrap an individual story if you only need the wrapper on a single story
 * export const OneOffExample = {decorators: [storyWrapper({pathname: '/kofta'})]}
 * ```
 */
export function storyWrapper(props: WrapperProps = {}) {
  return function WrapperDecorator(Story: StoryFn, context: StoryContext) {
    return (
      <Wrapper {...props} {...context.parameters.storyWrapper}>
        <Story />
      </Wrapper>
    )
  }
}

/**
 * Disables the `color-contrast` a11y rule for dialogs in Storybook.
 * This is needed because dialogs have an opacity animation that wrongly reports color contrast violations.
 */
export const disableA11yRuleForDialog = {config: {rules: [{id: 'color-contrast', enabled: false}]}}

/**
 * A helper function to wrap children in base providers. Useful for renderHook tests.
 * This can be used as the `wrapper` option in `renderHook` from `@testing-library/react`.
 *
 * BaseProviders are the providers that bootstrap React apps and partials that
 * give your app access to things like QueryClient, primer theming, analytics etc..
 *
 * @example
 * ```tsx
 * import {renderHook} from '@testing-library/react'
 * import {useMyHook} from './useMyHook'
 *
 * describe('useMyHook', () => {
 *  it('renders correctly with renderHook', () => {
 *   const wrapper = withBaseProvidersWrapper()
 *   const {result} = renderHook(() => useMyHook(), {wrapper})
 *   // assertions
 *  })
 * })
 * ```
 *
 * You can also bring your own providers by passing a function that wraps the children.
 * @example
 * ```tsx
 * import {renderHook} from '@testing-library/react'
 * import {useMyHook} from './useMyHook'
 * import {MyProvider} from './MyProvider'
 *
 * describe('useMyHook', () => {
 *  it('renders correctly with renderHook', () => {
 *   const wrapper = withBaseProvidersWrapper(({children}) => <MyProvider>{children}</MyProvider>)
 *   const {result} = renderHook(() => useMyHook(), {wrapper})
 *   // assertions
 *  })
 * })
 * ```
 * @param closure A function that wraps the children in additional providers
 * @returns A function that wraps the children in the base providers
 */
export function withBaseProvidersWrapper(closure?: (props: {children: ReactNode}) => ReactNode) {
  return function withBaseProvidersInner({children}: {children: ReactNode}) {
    return (
      <BaseProviders appName="withBaseProvidersWrapper" wasServerRendered={false} dataRouterEnabled={false}>
        {closure ? closure({children}) : children}
      </BaseProviders>
    )
  }
}

/**
 * Allows you to render a hook within a test React component without having to create that
 * component yourself.
 *
 * A wrapper around `@testing-library/react`'s `renderHook` that includes `withBaseProvidersWrapper`
 * as the default wrapper.
 */
export function renderHook<Result, Props>(
  renderFn: (initialProps: Props) => Result,

  options?: RenderHookOptions<Props> | undefined,
): RenderHookResult<Result, Props> {
  const wrapper = options?.wrapper
    ? // Perform an explicit cast because of their use of JSXElementConstructor<{children: React.ReactNode;}>
      withBaseProvidersWrapper(options.wrapper as (props: {children: ReactNode}) => ReactNode)
    : withBaseProvidersWrapper()

  return rtlRenderHook(renderFn, {
    ...options,
    wrapper,
  })
}
