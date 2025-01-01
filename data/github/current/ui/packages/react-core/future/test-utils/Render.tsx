import {
  type queries,
  render as rtlRender,
  renderHook as rtlRenderHook,
  type RenderHookOptions,
  type RenderHookResult as CoreRenderHookResult,
  type RenderOptions,
  type RenderResult as CoreRenderResult,
} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import type {Options as ImportedUserEventOptions, UserEvent} from '@testing-library/user-event'
// eslint-disable-next-line no-restricted-imports
import {userEvent} from '@testing-library/user-event'
import type {ReactNode} from 'react'
import {createMemoryRouter, type RouteObject, RouterProvider} from 'react-router-dom'

import {v7_routeProviderFutureFlags, v7_routerFutureFlags} from '../../react-router-future-flags'
import type {DataRouterApplication} from '../data-router-application'
import {routesWithProviders} from '../RoutesWithProviders'
import {
  createMemoryDataRouter,
  DataRouterAppWrapper,
  type DataRouterAppWrapperProps,
  type DataRouterAppWrapperRouterProps,
  DefaultHydrateFallback,
  defaultProfiler,
  getRouterOptions,
  type PathOrRouterOptions,
  type RouterOpts,
} from './DataRouterAppWrapper'

export const isJestEnvironment = () => typeof jest !== 'undefined'

export type UserEventOptions = ImportedUserEventOptions

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
  DataRouterAppWrapperProps & {
    pathOrRouterOptions: PathOrRouterOptions
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

export type RenderDataRouterAppOptions = DataRouterAppWrapperRouterProps &
  Omit<RenderOptions<typeof queries, HTMLElement, HTMLElement>, 'queries'> & {
    userEventOptions?: UserEventOptions
  }

/**
 * Renders an application given an app registration entry
 */
export function render(
  app: DataRouterApplication<string>,
  initialEntries: PathOrRouterOptions,
  {userEventOptions, appPayload, embeddedData, profiler = defaultProfiler, ...options}: RenderDataRouterAppOptions = {},
) {
  const router = createMemoryDataRouter({app, initialEntries, embeddedData, appPayload})

  return Object.assign(
    withUserEvent(
      rtlRender(<DataRouterAppWrapper app={app} router={router} profiler={profiler} />, options),
      userEventOptions,
    ),
    {router},
  )
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
): CoreRenderHookResult<Result, Props> & {router: ReturnType<typeof createMemoryRouter>} {
  const routerOptions = getRouterOptions(pathOrRouterOptions)
  const initialEntry = routerOptions.initialEntries?.at(-1) ?? '/'

  let router: ReturnType<typeof createMemoryRouter> | undefined

  const view = rtlRenderHook(hook, {
    ...options,
    wrapper: ({children}) => {
      router = createMemoryRouter(
        routesWithProviders(
          options?.getRoutes?.(children) ?? [
            {
              id: '__DATA_ROUTER_RENDER_HOOK_TEST_ROUTE__',
              path: typeof initialEntry === 'string' ? initialEntry : initialEntry.pathname ?? '/',
              element: children,
            },
          ],
          {
            appPayload,
            ssrError: undefined,
            appName: appName ?? 'test-app',
            wasServerRendered: false,
            HydrateFallback: DefaultHydrateFallback,
            dataRouterEnabled: true,
          },
        ),
        {
          ...routerOptions,
          future: v7_routerFutureFlags,
        },
      )

      return <RouterProvider router={router} future={v7_routeProviderFutureFlags} />
    },
  })

  if (!router) {
    throw new Error('Router was not created')
  }

  return Object.assign(view, {
    router,
  })
}
