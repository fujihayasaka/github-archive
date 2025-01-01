// @ts-check
import reactCorePackage from '../react-core/package.json' with {type: 'json'}
import reactNextPackage from '../react-next/package.json' with {type: 'json'}
import reactRouterNextPackage from '../react-router/package.json' with {type: 'json'}

const {NODE_ENV = 'development'} = process.env

/**
 * @param {boolean | undefined} reactNext
 */
export function getReactVersion(reactNext = false) {
  return reactNext ? reactNextPackage.dependencies.react : reactCorePackage.dependencies.react
}

export function getReactRouterVersion(isReactRouterNext = false) {
  return isReactRouterNext
    ? reactRouterNextPackage.dependencies['react-router']
    : reactCorePackage.dependencies['react-router-dom']
}

/**
 * @param {{bundler: string, reactVersion?: string, reactRouterVersion?: string, testRunner?: string}} options
 */
export function getDefinePluginConfig({bundler, reactVersion, reactRouterVersion}) {
  return {
    /**
     * styled-components <= 5 use a different
     * insertion method for styles between development and
     * production
     *
     * The development version is slower, because it writes
     * to the dom directly, then those values get parsed to the
     * cssom, where the production _speedy_ mode skips the dom step
     * writing straight the cssom
     *
     * Historically, browsers didn't allow modifying styles
     * in devtools if they were set in the cssom directly
     * (in effect, they were read-only). This is no longer the case
     * and we should be able to use the production mode in dev
     * without any issues.
     * https://github.com/styled-components/styled-components/issues/3320#issuecomment-719511773
     *
     * If you need to view the styles applied, generally,
     * you can do so from dev-tools via
     *
     * Get the styled-component style tag from the dom
     * const styleElement = document.querySelector<HTMLStyleElement>('style[data-styled]')
     * Log the text of the cssRules to the console, joined by newlines
     * console.log(styleElement.sheet?.cssRules.map(rule => rule.cssText).join('\n'))
     *
     * There could be multiple styled-component tags on a page, in which case
     * you may prefer to use `querySelectorAll` and iterate over the results from
     * each
     */
    SC_DISABLE_SPEEDY: 'false',

    /**
     * We want to be able to include information about the bundler used when we report stats/errors
     * to the server
     */
    BUNDLER: JSON.stringify(bundler),

    /**
     * We want to know the react version being used to show it in the staffbar so it's easier for
     * engineers to know which version they are using.
     */
    REACT_VERSION: JSON.stringify(reactVersion || getReactVersion()),

    /**
     * We want to know the react-router version being used to show it in the staffbar so it's easier for
     * engineers to know which version they are using.
     */
    REACT_ROUTER_VERSION: JSON.stringify(reactRouterVersion || getReactRouterVersion()),

    /**
     * Placeholder environment variables for Memex package. This will likely be deprecated as post-migration
     * work once we have this working as expected.
     */
    'process.env.ENABLE_PROFILING': 'false',
    'process.env.APP_ENV': JSON.stringify(NODE_ENV),
    /**
     * This is used to determine if memex is running in standalone mode. In this mode memex uses a msw mock server
     * instead of the monolith API, see: https://github.com/github/memex/blob/main/docs/developing-in-codespaces.md
     */
    'process.env.IS_STANDALONE': 'false',
    'process.env.DEBUG_RELAY': JSON.stringify(''),
  }
}

/**
 * @param {{bundler: string}} options
 */
export function getAlloyDefinePluginConfig({bundler}) {
  return {
    /**
     * We want to be able to include information about the bundler used when we report stats/errors
     * to the server
     */
    BUNDLER: JSON.stringify(bundler),

    /**
     * HTMLElement is not defined in Node.js. With some client code, such as Custom Elements,
     * we have `class MyElement extends HTMLElement` in code that runs at the top level. We don't
     * actually need these classes to fully function in SSR, but we do need some replacement for the
     * global HTMLElement references. To keep things simple, we just swap these with `Object` which is
     * defined globally and can be extended.
     */
    HTMLElement: 'Object',

    /**
     * We want to force a server-like environment, even if we are running in a browser-like environment
     * This helps with environments like the alloy-profiling tool, which runs the Alloy bundle in a browser.
     */
    FORCE_SERVER_ENV: 'true',

    /**
     * Used by testIdProps to avoid adding `data-testid` attributes to the DOM in production.
     */
    'process.env.APP_ENV': JSON.stringify(NODE_ENV),
  }
}
