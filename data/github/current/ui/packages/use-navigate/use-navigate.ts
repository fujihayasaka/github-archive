import React, {startTransition} from 'react'
import {
  createPath,
  createSearchParams,
  matchRoutes,
  resolvePath,
  useLocation,
  useNavigate as useReactRouterNavigate,
  useSearchParams as useReactRouterSearchParams,
  type NavigateOptions,
  type To,
  type URLSearchParamsInit,
} from 'react-router-dom'

import isHashNavigation from '@github-ui/is-hash-navigation'
import {startSoftNav} from '@github-ui/soft-nav/state'
import {PREVENT_AUTOFOCUS_KEY} from '@github-ui/react-core/prevent-autofocus'
import {RoutesContext} from '@github-ui/react-core/routes-context'

export interface NavigateOptionsWithPreventAutofocus extends NavigateOptions {
  preventAutofocus?: boolean
  reloadDocument?: boolean
}

export const useNavigate = (): ((to: To, options?: NavigateOptionsWithPreventAutofocus) => void) => {
  const {routes} = React.useContext(RoutesContext)
  const reactRouterNavigate = useReactRouterNavigate()
  return React.useCallback(
    (to, navigateOptions = {}) => {
      const pathname = resolvePath(to).pathname
      const isExternalToApp = !matchRoutes(routes, pathname)

      if (isExternalToApp || navigateOptions.reloadDocument) {
        const href = typeof to === 'string' ? to : createPath(to)
        ;(async () => {
          const {softNavigate: turboSoftNavigate} = await import('@github-ui/soft-navigate')
          turboSoftNavigate(href)
        })()
      } else {
        if (!isHashNavigation(location.href, to.toString())) {
          startSoftNav('react')
        }
        const {preventAutofocus, ...options} = navigateOptions
        startTransition(() => {
          reactRouterNavigate(
            to,
            preventAutofocus
              ? {
                  ...options,
                  state: {
                    [PREVENT_AUTOFOCUS_KEY]: true,
                    ...options.state,
                  },
                }
              : options,
          )
        })
      }
    },
    [reactRouterNavigate, routes],
  )
}

/**
 * An implementation of `useSearchParams` that mirrors `react-router-dom`'s `useSearchParams` hook
 * but utilizes `@github-ui/useNavigate` instead of `react-router` `useNavigate` to handle updates.
 */
export const useSearchParams = () => {
  const [searchParams] = useReactRouterSearchParams()
  const navigate = useNavigate()
  const {pathname} = useLocation()

  const setSearchParams = React.useCallback<
    (
      nextInit?: URLSearchParamsInit | ((prev: URLSearchParams) => URLSearchParamsInit),
      navigateOpts?: NavigateOptionsWithPreventAutofocus,
    ) => void
  >(
    (nextInit, navigateOptions = {}) => {
      const newSearchParams = createSearchParams(typeof nextInit === 'function' ? nextInit(searchParams) : nextInit)
      navigate(
        {
          pathname,
          search: newSearchParams.toString(),
        },
        navigateOptions,
      )
    },
    [searchParams, navigate, pathname],
  )

  return [searchParams, setSearchParams] as const
}
