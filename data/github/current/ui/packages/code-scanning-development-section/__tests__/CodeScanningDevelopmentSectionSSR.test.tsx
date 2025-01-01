/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCodeScanningDevelopmentSectionProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../entry'

describe('code-scanning-development-section SSR', () => {
  test('Renders no linked pull requests or branches', async () => {
    const props = getCodeScanningDevelopmentSectionProps()
    const view = await serverRenderReact({
      name: 'code-scanning-development-section',
      data: {props},
    })

    // verify ssr was able to render some content from the props
    expect(view).toMatch('Development')
    expect(view).toMatch('No linked branches or pull requests.')
  })

  test('Renders 1 linked pull request and 1 branch', async () => {
    const props = getCodeScanningDevelopmentSectionProps({withAlertLinks: true})
    const view = await serverRenderReact({
      name: 'code-scanning-development-section',
      data: {props},
    })

    // verify ssr was able to render some content from the props
    expect(view).toMatch('Development')
    expect(view).not.toMatch('No linked branches or pull requests.')
    expect(view).toMatch('fix-alert-1') // fixture branch name
    expect(view).toMatch('Fix alert 1') // fixture pull request title
  })
})
