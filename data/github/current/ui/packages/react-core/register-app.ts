// Import the web component to get it registered on the window
import './ReactAppElement'

import {createDataRouterAppRegistration, reactDataRouterAppDeferredRegistry} from './future/data-router-app-registry'
import type {DataRouterApplication} from './future/data-router-application'
import {
  createNavigatorAppRegistration,
  type NavigatorAppRegistrationFn,
  reactNavigatorAppDeferredRegistry,
} from './navigator-app-registry'

/**
 * NOTE: if the signature of this method changes, also update the react-app-name ESLint rule
 * /ui/packages/eslint-plugin-github-monorepo/rules/react-app-name.js
 *
 * @deprecated This API is deprecated and is no longer supported. Consider migrating to DataRouter and use `registerDataRouterApp` instead (https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router).
 */
export function registerNavigatorApp(appName: string, registration: NavigatorAppRegistrationFn): void {
  reactNavigatorAppDeferredRegistry.register(appName, createNavigatorAppRegistration(registration))
}

export function registerDataRouterApp<T extends string>(app: DataRouterApplication<T>): void {
  reactDataRouterAppDeferredRegistry.register(app.name, createDataRouterAppRegistration(app.registration))
}
