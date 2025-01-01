import type {Router, RouterNavigateOptions, To} from '@remix-run/router'

const overrideMap = new WeakMap<Router, true>()
export function applyRouterNavigateOverride(router: Router): void {
  /** only apply once per router instance */
  if (overrideMap.get(router)) return
  overrideMap.set(router, true)

  const routerNavigate = router.navigate.bind(router)

  /**
   * @internal
   * PRIVATE - DO NOT USE - we define this to match the react-router navigate type, but don't expose it
   *
   * Navigate forward/backward in the history stack
   * @param to Delta to move in the history stack
   */
  function navigateOverride(to: number): Promise<void>
  /**
   * Navigate to the given path
   * @param to Path to navigate to
   * @param opts Navigation options (method, submission, etc.)
   */
  function navigateOverride(to: To | null, opts?: RouterNavigateOptions): Promise<void>
  function navigateOverride(to: To | null | number, opts?: RouterNavigateOptions): Promise<void> {
    if (typeof to === 'number') {
      return routerNavigate(to)
    }

    const isPushAction = !opts?.replace
    const skipTurboState = opts?.state?.skipTurbo

    return routerNavigate(to, {
      ...opts,
      state: {
        ...opts?.state,
        /**
         * When the historyAction is 'push' we default to setting `skipTurbo` to true if it isn't set when we
         * call navigate
         */
        skipTurbo: isPushAction ? skipTurboState ?? true : skipTurboState,
      },
    })
  }

  router.navigate = navigateOverride
}
