import {readFile} from 'fs/promises'
import {Script} from 'vm'
import {fileURLToPath} from 'url'
import {dirname, resolve} from 'path'
import {allowedSandboxGlobals} from './vm.ts'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

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
 * This smoke test will assume the alloy assets are already built in public/assets
 */
function readPublicAsset(relativePath: string) {
  const path = resolve(__dirname, `../../../public/assets/${relativePath}`)
  return readFile(path, 'utf-8')
}

/**
 * Build a vm Script, similar to how we do it in Alloy. Note, this is missing some of the
 * additional reset wrapping that Alloy does, but it is sufficient for a smoke test.
 */
async function buildAlloyScript() {
  const manifestContent = await readPublicAsset('manifest.alloy.json')
  const manifest = JSON.parse(manifestContent)
  console.log(`Running Alloy smoke test with ${manifest.entries.alloy}`)
  const alloyContent = await readPublicAsset(manifest.entries.alloy)
  const script = new Script(`
    const module = {};
    ${alloyContent}
    module.exports
  `)
  return script.runInNewContext(allowedSandboxGlobals)
}

async function alloySmokeTest() {
  const setup = await buildAlloyScript()

  // Render the react sandbox
  const handler = setup()
  const result = await handler(reactSandboxPayload)

  // Verify the output
  if (typeof result !== 'string') {
    throw new Error(`Expected React Sandbox to render a string, got "${typeof result}"`)
  } else if (!result.toLowerCase().includes('react sandbox')) {
    throw new Error('Expected React Sandbox to include "react sandbox" in the output')
  }

  // Reset and render again
  const handler2 = setup()
  const result2 = await handler2(reactSandboxPayload)

  if (result2 !== result) {
    /**
     * If the result is different, it could be a number of different things:
     * - A bug in the alloy bundle setup, where resets aren't working
     * - A random number/result being generated on the React Sandbox page
     * - A problem with other tooling, such as styled-components
     */
    throw new Error(
      'Alloy rendered different results for React Sandbox after a reset. The results should be consistent given the same payload between isolated renders.',
    )
  }
}

console.time('Alloy smoke test')
await alloySmokeTest()
console.timeEnd('Alloy smoke test')
