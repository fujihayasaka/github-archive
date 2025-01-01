import {render, screen} from '@testing-library/react'

import {ContentfulBreadcrumbs} from '../../../../components/contentful/ContentfulBreadcrumbs/ContentfulBreadcrumbs'
import type {PrimerComponentBreadcrumb} from '../../../../schemas/contentful/contentTypes/primerComponentBreadcrumb'

const breadcrumbs: PrimerComponentBreadcrumb[] = [
  {
    sys: {
      id: '3sKZC4xN2iI7ZQNe67u7Qc',
      contentType: {
        sys: {
          id: 'primerComponentBreadcrumb',
        },
      },
    },
    fields: {
      pageName: 'Github Foo',
      path: '/',
      selected: false,
    },
  },
  {
    sys: {
      id: '2K1uZ0LfldssUOdNSEwPY',
      contentType: {
        sys: {
          id: 'primerComponentBreadcrumb',
        },
      },
    },
    fields: {
      pageName: 'Contentful LP Test',
      path: '/contentful-lp-test',
      selected: false,
    },
  },
  {
    sys: {
      id: '3aKzjXZN9SMfEgldSel7sM',
      contentType: {
        sys: {
          id: 'primerComponentBreadcrumb',
        },
      },
    },
    fields: {
      pageName: 'Flex Template',
      path: '/contentful-lp-tests/template-flex',
      selected: true,
    },
  },
]

describe('ContentfulBreadcrumbs', () => {
  it('Renders the Breadcrumb text', () => {
    render(<ContentfulBreadcrumbs variant="default" breadcrumbs={breadcrumbs} />)

    expect(screen.getByText('Github Foo').getAttribute('href')).toBe('/')
    expect(screen.getByText('Contentful LP Test').getAttribute('href')).toBe('/contentful-lp-test')
    expect(screen.getByText('Flex Template').getAttribute('href')).toBe('/contentful-lp-tests/template-flex')
  })
})
