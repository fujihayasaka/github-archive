import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {ToastContextProvider} from '@github-ui/toast/ToastContext'
import {AliveTestProvider} from '@github-ui/use-alive/test-utils'
import {ThemeProvider} from '@primer/react'
import type {InitialEntry} from '@remix-run/router'
import type {StoryContext, StoryFn} from '@storybook/react'
import {QueryClientProvider} from '@tanstack/react-query'
import {
  render as rtlRender,
  renderHook as rtlRenderHook,
  type RenderResult as CoreRenderResult,
  type RenderHookResult as CoreRenderHookResult,
  type queries,
  type RenderOptions,
  type RenderHookOptions,
} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import type {Options as ImportedUserEventOptions, UserEvent} from '@testing-library/user-event'
import {Profiler, useEffect, type ComponentType, type FC, type ProfilerOnRenderCallback, type ReactNode} from 'react'
import {
  createMemoryRouter,
  RouterProvider,
  useLocation,
  type IndexRouteObject,
  type Location,
  type NonIndexRouteObject,
  type RouteObject,
} from 'react-router-dom'
import {CommonElements} from '../../CommonElements'
import type {EmbeddedData} from '../../embedded-data-types'
import {getQueryClient} from '../../query-client'
import {v7_routeProviderFutureFlags, v7_routerFutureFlags} from '../../react-router-future-flags'
import {applyRouterNavigateOverride} from '../apply-router-navigate-override'
import type {DataRouterApplication} from '../data-router-application'
import {routesWithProviders} from '../RoutesWithProviders'

export type UserEventOptions = ImportedUserEventOptions
// user-event attaches afterEach and afterAll hooks that reset the clipboard mocks after every test. So if we always
// import it and an SSR-only test imports this (ie, through a utils file that is shared with non-SSR tests), it will
// error on cleanup when user-event tries to access `navigator.clipboard`.
const userEvent: UserEvent | null =
  typeof document !== 'undefined'
    ? // eslint-disable-next-line @typescript-eslint/no-require-imports
      require('@testing-library/user-event').userEvent
    : null

type RouterOpts = Pick<
  NonNullable<Parameters<typeof createMemoryRouter>[1]>,
  'initialEntries' | 'initialIndex' | 'hydrationData'
>

type OmittedRouteObjectKeys = 'element' | 'Component' | 'lazy'

type WrapperProps = RouterOpts & {
  appName?: string
  HydrateFallback?: ComponentType
  route?: Omit<IndexRouteObject, 'element' | 'Component' | 'lazy'> | Omit<NonIndexRouteObject, OmittedRouteObjectKeys>
  children?: ReactNode
}

function DefaultHydrateFallback() {
  return <div>loading...</div>
}

const defaultInitialEntries = ['/']

const defaultRoute = {
  path: '/',
  HydrateFallback: DefaultHydrateFallback,
} satisfies RouteObject

export const Wrapper: FC<WrapperProps> = ({
  appName = 'test-app',
  children,
  initialEntries = defaultInitialEntries,
  initialIndex = 0,
  route,
}) => {
  const routes = [
    {
      ...defaultRoute,
      ...route,
      element: (
        <ToastContextProvider>
          <>{children}</>
          <RouteContext />
          <CommonElements />
        </ToastContextProvider>
      ),
    },
  ] satisfies RouteObject[]

  const router = createMemoryRouter(routes, {
    initialEntries,
    initialIndex,
    future: v7_routerFutureFlags,
  })

  applyRouterNavigateOverride(router)

  return (
    <QueryClientProvider client={getQueryClient()}>
      <ThemeProvider>
        <AnalyticsProvider appName={appName} category="" metadata={{}}>
          <RouterProvider router={router} future={v7_routeProviderFutureFlags} />
        </AnalyticsProvider>
      </ThemeProvider>
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

  const coreUser = userEvent.setup({
    advanceTimers: delay => {
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

type RouterOptionsWithEntries = {initialEntries: InitialEntry[] | undefined; initialIndex?: number | undefined}
type PathOrRouterOptions = string | string[] | RouterOptionsWithEntries
type RenderDataRouterAppOptions = Omit<RenderOptions<typeof queries, HTMLElement, HTMLElement>, 'queries'> & {
  appPayload?: Record<string, unknown>
  embeddedData?: EmbeddedData
  userEventOptions?: UserEventOptions
  profiler?: {
    onRender: ProfilerOnRenderCallback
  }
}

function getRouterOptions(pathOrRouterOptions: PathOrRouterOptions): RouterOptionsWithEntries {
  if (Array.isArray(pathOrRouterOptions)) {
    return {
      initialEntries: pathOrRouterOptions,
    }
  }

  if (typeof pathOrRouterOptions === 'string') {
    return {
      initialEntries: [pathOrRouterOptions],
    }
  }

  return pathOrRouterOptions
}

/**
 * Renders an application given an app registration entry
 */
export async function render(
  app: DataRouterApplication<string>,
  pathOrRouterOptions: PathOrRouterOptions,
  {
    userEventOptions,
    appPayload,
    embeddedData,
    profiler = {onRender: jest.fn()},
    ...options
  }: RenderDataRouterAppOptions = {},
) {
  const {routes} = app.registration({...(embeddedData && {embeddedData})})

  const router = createMemoryRouter(
    routesWithProviders(routes, {
      appPayload: appPayload ?? embeddedData?.appPayload,
      ssrError: undefined,
      appName: app.name,
      wasServerRendered: false,
      HydrateFallback: DefaultHydrateFallback,
      children: <RouteContext />,
      dataRouterEnabled: true,
    }),
    {
      ...getRouterOptions(pathOrRouterOptions),
      future: v7_routerFutureFlags,
    },
  )

  return Object.assign(
    withUserEvent(
      rtlRender(
        <AliveTestProvider>
          <Profiler id={app.name} onRender={profiler.onRender}>
            <RouterProvider router={router} future={v7_routeProviderFutureFlags} />
          </Profiler>
        </AliveTestProvider>,
        options,
      ),
      userEventOptions,
    ),
    {router},
  )
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

export function renderHook<Result, Props>(
  hook: (props: Props) => Result,
  pathOrRouterOptions: PathOrRouterOptions,
  {
    appPayload,
    appName,
    ...options
  }: RenderHookOptions<Props, typeof queries, HTMLElement, HTMLElement> &
    RouterOpts & {
      getRoutes?: (children: ReactNode) => RouteObject[]
    } & {appPayload?: Record<string, unknown>; appName?: string} = {},
): CoreRenderHookResult<Result, Props> {
  const routerOptions = getRouterOptions(pathOrRouterOptions)
  const initialEntry = routerOptions.initialEntries?.at(-1) ?? '/'

  return rtlRenderHook(hook, {
    ...options,
    wrapper: ({children}) => {
      const memoryRouter = createMemoryRouter(
        routesWithProviders(
          options?.getRoutes?.(children) ?? [
            {path: typeof initialEntry === 'string' ? initialEntry : initialEntry.pathname ?? '/', element: children},
          ],
          {
            appPayload,
            ssrError: undefined,
            appName: appName ?? 'test-app',
            wasServerRendered: false,
            HydrateFallback: DefaultHydrateFallback,
            children: <RouteContext />,
            dataRouterEnabled: true,
          },
        ),
        {
          ...routerOptions,
          future: v7_routerFutureFlags,
        },
      )

      return <RouterProvider router={memoryRouter} future={v7_routeProviderFutureFlags} />
    },
  })
}
