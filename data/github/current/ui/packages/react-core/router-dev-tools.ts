import type {Location, RouteObject, UIMatch} from 'react-router-dom'

export type RouterState = {
  location: Location
  matches: UIMatch[]
  routes: StaticUiMatch[]
}

export type RouteStateUpdateListener = (state: RouterState | null) => void

type StaticUiMatch = Omit<UIMatch, 'params' | 'data' | 'handle'> & {route: RouteObject}
const ROUTE_START_UPDATE_EVENT_TYPE = '@github-ui/react-core/router:state-update'

class RouterStateUpdateEvent extends Event {
  constructor() {
    super(ROUTE_START_UPDATE_EVENT_TYPE)
  }
}

class RouterStore extends EventTarget {
  static #instance: RouterStore
  #state: RouterState | null = null

  /**
   * Private constructor to enforce singleton pattern
   */
  private constructor() {
    super()
  }

  /**
   * Static method to get the singleton instance
   */
  static getInstance(): RouterStore {
    if (!RouterStore.#instance) {
      RouterStore.#instance = new RouterStore()
    }
    return RouterStore.#instance
  }

  getState(): RouterState | null {
    return this.#state
  }

  setState(state: RouterState | null): void {
    this.#state = state
    this.dispatchEvent(new RouterStateUpdateEvent())
  }

  /**
   * Subscribe to state changes
   * The listener will be called with the current state immediately and then on every state change
   * @returns A function to unsubscribe from state changes
   * @example
   * const unsubscribe = store.subscribe((state) => {
   *   console.log('State changed:', state)
   * })
   * // Later, to unsubscribe:
   * unsubscribe()
   */
  subscribe(listener: RouteStateUpdateListener): () => void {
    const controller = new AbortController()

    this.addEventListener(
      ROUTE_START_UPDATE_EVENT_TYPE,
      () => {
        listener(this.#state)
      },
      {signal: controller.signal},
    )

    listener(this.#state)

    return () => {
      controller.abort()
    }
  }
}

/**
 * Get the singleton instance of the RouterStore
 * @returns The singleton instance of the RouterStore`
 */
export function getRouterDevtoolsStore(): RouterStore {
  return RouterStore.getInstance()
}
