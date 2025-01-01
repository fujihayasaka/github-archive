import {describe, expect, it} from '@github-ui/tests'
import {renderToString} from 'react-dom/server'

import {PageBannerOutlet} from '../PageBannerContext'

describe('PageBannerOutlet', () => {
  it('renders nothing on the server', () => {
    // Note; this only works because we legit return null
    // If we ever want to support server rendered banners this test will need to change
    // eslint-disable-next-line testing-library/render-result-naming-convention
    const string = renderToString(<PageBannerOutlet />)
    expect(string).toBe('')
  })
})
