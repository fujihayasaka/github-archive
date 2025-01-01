// Import the web component to get it registered on the window
import './ReactPartialElement'

import {type PartialRegistration, partialRegistry} from './react-partial-registry'

// NOTE: if the signature of this method changes, also update the react-partial-name ESLint rule
// /workspaces/github/ui/packages/eslint-plugin-github-monorepo/rules/react-partial-name.js
export function registerReactPartial(name: string, registration: PartialRegistration) {
  return partialRegistry.register(name, registration)
}
