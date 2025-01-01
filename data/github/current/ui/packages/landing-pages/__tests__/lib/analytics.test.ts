import {cohortFunnelBuilder} from '../../lib/analytics'

describe('cohortFunnelBuilder', () => {
  it('adding cft param to path', () => {
    const cft = 'test_funnel'
    const path = '/features/copilot'
    const withCft = cohortFunnelBuilder(cft)

    const newPath = withCft(path)

    expect(newPath).toBe('/features/copilot?cft=test_funnel')
  })

  it('appending product to cft param', () => {
    const cft = 'test_funnel'
    const path = '/features/copilot'
    const withCft = cohortFunnelBuilder(cft)

    const newPath = withCft(path, {product: 'copilot'})

    expect(newPath).toBe('/features/copilot?cft=test_funnel.copilot')
  })

  it('adding cft param to return_to query param', () => {
    const cft = 'test_funnel'
    const path = '/features/copilot?return_to=%2Fdashboard%3Ffoo%3Dbar'
    const withCft = cohortFunnelBuilder(cft)

    const newPath = withCft(path)

    expect(newPath).toBe('/features/copilot?return_to=%2Fdashboard%3Ffoo%3Dbar%26cft%3Dtest_funnel&cft=test_funnel')
  })

  it('returning empty string if path is undefined', () => {
    const withCft = cohortFunnelBuilder('test_funnel')
    const nonexistent = undefined

    expect(withCft(nonexistent)).toBe('')
  })
})
