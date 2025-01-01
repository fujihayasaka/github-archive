describe('Relay routes are in index.ts files', () => {
  test('All relay routes are in index.ts files', async () => {
    jest.spyOn(console, 'table').mockImplementation()
    jest.spyOn(console, 'log').mockImplementation()
    /**
     * Dynamic because we need to mock the console calls _before_ we import it
     */
    const {getGithubReactRoutes} = await import('../react-audit')
    const allRoutes = getGithubReactRoutes()
    const relayRoutes = allRoutes.filter(route => route['route type'] === 'relayRoute')
    const nonIndexRoutes = relayRoutes.filter(route => !route.file.endsWith('index.ts'))
    expect(nonIndexRoutes).toEqual([])
  })
})
