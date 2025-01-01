import {appRegistryFactory, type AppRegistrationFn} from './react-app-registry'
// Import the web component to get it registered on the window
import './ReactAppElement'

// NOTE: if the signature of this method changes, also update the react-app-name ESLint rule
// /ui/packages/eslint-plugin-github-monorepo/rules/react-app-name.js
export function registerReactAppFactory(appName: string, factory: AppRegistrationFn) {
  appRegistryFactory.register(appName, factory)
}
