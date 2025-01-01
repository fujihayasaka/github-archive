// @ts-check

/**
 * @param {string} filePath
 */
function isPrimerReactCssFile(filePath) {
  if (!filePath.includes('node_modules/@primer/react') && !filePath.includes('primer/react/packages/react/lib-esm')) {
    return false
  }

  return filePath.endsWith('.css')
}

/**
 * This plugin wraps the primer/react css modules in a `@layer primer-react` directive. This helps
 * ensure css is applied in the correct order, regardless of when it's loaded on the page.
 *
 * @param {string} source The source code of the file being transformed
 * @param {string} filePath The path to the file being transformed
 */
export function wrapCssInPrimerReactLayer(source, filePath) {
  // Only patch primer react css files
  if (!isPrimerReactCssFile(filePath) || !source) {
    return
  }

  return `@layer primer-react { ${source} }`
}
