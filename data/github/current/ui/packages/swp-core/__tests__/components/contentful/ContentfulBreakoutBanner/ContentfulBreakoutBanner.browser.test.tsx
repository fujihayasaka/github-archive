import {BLOCKS} from '@contentful/rich-text-types'
import {render, screen} from '@testing-library/react'

import {describe, expect, it} from '@github-ui/tests'

import {ContentfulBreakoutBanner} from '../../../../components/contentful/ContentfulBreakoutBanner/ContentfulBreakoutBanner'
import type {PrimerComponentBreakoutBanner} from '../../../../schemas/contentful/contentTypes/primerComponentBreakoutBanner'

const contentfulBreakoutBannerFixture: PrimerComponentBreakoutBanner = {
  sys: {
    id: '5FAWEzIilOaiABd9mBszkR',
    contentType: {
      sys: {
        id: 'primerComponentBreakoutBanner',
      },
    },
  },
  fields: {
    align: 'start',
    backgroundImage: {
      fields: {
        description: 'A horizontal background for a breakout banner',
        file: {
          url: '//images.ctfassets.net/8aevphvgewt8/qZAOIUgxosFxftpHMTQzj/9d85bd00cb68430615cb9acb1522acc6/dark-horizontal-banner.png',
        },
      },
    },
    ctaLink: {
      sys: {
        id: '2bUcgWPqK5N4vfZw3ik20X',
        contentType: {
          sys: {
            id: 'link',
          },
        },
      },
      fields: {
        href: '#',
        text: 'Primary Action',
        openInNewTab: false,
      },
    },
    heading: {
      nodeType: BLOCKS.DOCUMENT,
      data: {},
      content: [
        {
          data: {},
          content: [
            {
              data: {},
              marks: [],
              value: 'A Heading For the Breakout Banner',
              nodeType: 'text',
            },
          ],
          nodeType: BLOCKS.PARAGRAPH,
        },
        {
          data: {},
          content: [
            {
              data: {},
              marks: [],
              value: '',
              nodeType: 'text',
            },
          ],
          nodeType: BLOCKS.PARAGRAPH,
        },
      ],
    },
    logo: 'Gartner',
  },
}

describe('ContentfulBreakoutBanner', () => {
  it('renders the Hero component', () => {
    render(<ContentfulBreakoutBanner component={contentfulBreakoutBannerFixture} />)
    expect(screen.getByTitle('Gartner')).toBeInTheDocument()
    expect(screen.getByText('A Heading For the Breakout Banner')).toBeInTheDocument()
    expect(screen.getByText('Primary Action')).toBeInTheDocument()
  })
})
