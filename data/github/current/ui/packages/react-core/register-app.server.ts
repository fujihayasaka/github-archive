import type {DataRouterAppRegistrationObject} from './future/data-router-app-registry'
import {createDataRouterAppRegistration} from './future/data-router-app-registry'
import type {DataRouterApplication} from './future/data-router-application'
import type {NavigatorAppRegistrationFn, NavigatorAppRegistrationObject} from './navigator-app-registry'
import {createNavigatorAppRegistration} from './navigator-app-registry'

// As of early 2025, most existing apps are navigator apps. The newer thing is
// to use the data router. We'll need both as we're slowly transitioning from
// navigator apps to data router apps. Eventually, we'll only have the
// data router registry and in that future, we can rename this to `reactAppRegistry`
// if we wanted to.
export const reactNavigatorAppSyncRegistry = new Map<string, NavigatorAppRegistrationObject>()
export const reactDataRouterAppSyncRegistry = new Map<string, DataRouterAppRegistrationObject>()

/**
 * This is a shim for the registerNavigatorApp function. The standard version uses promises
 * to handle delayed registration, but we can rely on synchronous registration in
 * the Alloy bundle. This shim is injected via webpack
 **/
export function registerNavigatorApp(appName: string, registration: NavigatorAppRegistrationFn): void {
  reactNavigatorAppSyncRegistry.set(appName, createNavigatorAppRegistration(registration))
}

/**
 * This is a shim for the registerDataRouterApp function. The standard version uses promises
 * to handle delayed registration, but we can rely on synchronous registration in
 * the Alloy bundle. This shim is injected via webpack
 **/
export function registerDataRouterApp<T extends string>(app: DataRouterApplication<T>): void {
  reactDataRouterAppSyncRegistry.set(app.name, createDataRouterAppRegistration(app.registration))
}
