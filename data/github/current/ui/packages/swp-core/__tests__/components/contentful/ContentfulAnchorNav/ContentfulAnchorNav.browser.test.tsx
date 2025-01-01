import {render, screen} from '@testing-library/react'

import {describe, expect, it} from '@github-ui/tests'

import {ContentfulAnchorNav} from '../../../../components/contentful/ContentfulAnchorNav/ContentfulAnchorNav'

describe('ContentfulAnchorNav', () => {
  it('Renders the AnchorNav correctly', () => {
    render(
      <ContentfulAnchorNav
        component={{
          sys: {id: 'example-nav', contentType: {sys: {id: 'primerComponentAnchorNav'}}},
          fields: {
            links: [
              {
                sys: {id: 'example-link', contentType: {sys: {id: 'primerComponentAnchorLink'}}},
                fields: {href: 'foo', text: 'Example anchor link'},
              },
            ],
            action: {
              sys: {id: 'example-action', contentType: {sys: {id: 'link'}}},
              fields: {href: '#action', text: 'Example action'},
            },
          },
        }}
      />,
    )

    expect(screen.getByTestId('example-link-anchor-link')).toHaveAttribute('href', '#foo')
  })
})
