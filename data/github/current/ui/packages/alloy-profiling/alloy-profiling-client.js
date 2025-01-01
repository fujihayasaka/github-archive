/**
 * These are globals which need to be mocked to simulate the Alloy server environment
 */
globalThis.Readable = class Readable {}
globalThis.require = function require(name) {
  if (name === 'stream') {
    return {Readable: globalThis.Readable}
  }
  if (name === 'util') {
    return {
      TextEncoder,
    }
  }
}
globalThis.module = {}
const document = globalThis.document

/**
 * When in a browser, some of our dependencies create additional globals
 * These aren't a concern as they aren't created in the server environment
 */
globalThis.ALLOWED_GLOBAL_KEYS = [
  '__REACT_DEVTOOLS_BACKEND_MANAGER_INJECTED__',
  '__reactRouterVersion',
  '__styled-components-init__',
  '__THREE__',
  'applyFocusVisiblePolyfill',
  'RelativeTimeElement',
]

/**
 * This is an example payload for the react sandbox
 */
const reactSandboxPayload = {
  name: 'react-sandbox',
  path: 'https://github.com/_react_sandbox/alloy',
  url: 'https://github.com/_react_sandbox/alloy',
  data: {
    payload: {
      name: 'alloy',
    },
    title: 'Alloy SSR',
    locale: 'en',
    appPayload: null,
  },
  colorModes: {
    colorMode: 'light',
    lightTheme: 'light',
    darkTheme: 'dark',
  },
  clientEnv: {
    locale: 'en',
    featureFlags: [],
  },
}

/**
 * Reset will call the default export (setup) function from the bundle
 */
let handler
function reset() {
  document.getElementById('output').textContent = ''
  performance.mark('reset-start')
  const setup = globalThis.module.exports
  handler = setup()
  performance.mark('reset-end')
  const resetTime = performance.measure('reset-time', 'reset-start', 'reset-end').duration
  const resetMessage = `${resetTime.toFixed(2)} ms`
  document.getElementById('reset-time').textContent = resetMessage
  console.log('Reset took ', resetMessage)
}

/**
 * Render will call the handler function, passing in the args from the textarea
 * If the handler has not yet been created, reset will be called first
 */
async function render() {
  if (!handler) {
    console.log('Handler not initialized')
    reset()
  }
  performance.mark('render-start')
  const html = await handler(JSON.parse(document.getElementById('args').value))
  performance.mark('render-end')
  document.getElementById('output').innerHTML = html
  const renderTime = performance.measure('render-time', 'render-start', 'render-end').duration
  const renderMessage = `${renderTime.toFixed(2)} ms`
  document.getElementById('render-time').textContent = renderMessage
}

/**
 * This will load the Alloy bundle, followed by enabling the buttons on the page
 */
async function loadAlloyBundle() {
  // eslint-disable-next-line import/no-unresolved, import/no-absolute-path
  await import('/alloy.js')
  console.log('Alloy bundle loaded')
  for (const button of document.querySelectorAll('button')) {
    button.removeAttribute('disabled')
  }
}

document.addEventListener('DOMContentLoaded', async () => {
  document.getElementById('reset').addEventListener('click', reset)
  document.getElementById('render').addEventListener('click', render)
  document.getElementById('args').value = JSON.stringify(reactSandboxPayload, null, 2)
})

await loadAlloyBundle()
