import {wrapCssInPrimerReactLayer} from '../primer-react-css-layer'

describe('primer react css layer', () => {
  it('should wrap the css source code in a primer-react layer', () => {
    const source = 'my css code'
    const expectedResult = `@layer primer-react { ${source} }`

    // example from local primer development
    expect(
      wrapCssInPrimerReactLayer(source, '/primer/react/packages/react/lib-esm/some-component/some-module.css'),
    ).toBe(expectedResult)
  })

  it('should return undefined if the path is not a primer css file', () => {
    expect(
      wrapCssInPrimerReactLayer('source', '/node_modules/@primer/react/some-component/some-module.js'),
    ).toBeUndefined()
    expect(
      wrapCssInPrimerReactLayer('source', '/primer/react/packages/react/lib-esm/some-component/some-module.ts'),
    ).toBeUndefined()
    expect(wrapCssInPrimerReactLayer('source', '/ui/packages/some-package/some-module.css')).toBeUndefined()
  })
})
