import type {DataRouterApplication} from './future/data-router-application'
import {
  createNavigatorAppRegistration,
  reactNavigatorAppDeferredRegistry,
  type NavigatorAppRegistrationFn,
} from './navigator-app-registry'
import {createDataRouterAppRegistration, reactDataRouterAppDeferredRegistry} from './future/data-router-app-registry'

// Import the web component to get it registered on the window
import './ReactAppElement'

// NOTE: if the signature of this method changes, also update the react-app-name ESLint rule
// /ui/packages/eslint-plugin-github-monorepo/rules/react-app-name.js
export function registerNavigatorApp(appName: string, registration: NavigatorAppRegistrationFn): void {
  reactNavigatorAppDeferredRegistry.register(appName, createNavigatorAppRegistration(registration))
}

export function registerDataRouterApp<T extends string>(app: DataRouterApplication<T>): void {
  reactDataRouterAppDeferredRegistry.register(app.name, createDataRouterAppRegistration(app.registration))
}
