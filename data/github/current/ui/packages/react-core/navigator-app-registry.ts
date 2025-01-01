import type {AppRegistration, NavigatorRouteRegistration} from './app-routing-types'
import {DeferredRegistry} from './deferred-registry'

export interface NavigatorAppRegistration extends AppRegistration {
  App?: React.ComponentType<{children?: React.ReactNode}>
  routes: NavigatorRouteRegistration[]
}

export type NavigatorAppRegistrationFn = () => NavigatorAppRegistration

export type NavigatorAppRegistrationObject = {type: 'NavigatorApp'; registration: NavigatorAppRegistrationFn}

export function createNavigatorAppRegistration(
  registration: NavigatorAppRegistrationFn,
): NavigatorAppRegistrationObject {
  return {
    type: 'NavigatorApp',
    registration,
  }
}

export const reactNavigatorAppDeferredRegistry = new DeferredRegistry<NavigatorAppRegistrationObject>()

export async function getReactNavigatorApp(appName: string) {
  return reactNavigatorAppDeferredRegistry.getRegistration(appName).promise
}
