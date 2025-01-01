import SidebarHeading from '../SidebarHeading'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('SidebarHeading', () => {
  describe('When there is no link', () => {
    test('Does not render a link', () => {
      render(<SidebarHeading title="Title" />)

      expect(screen.queryByRole('link')).not.toBeInTheDocument()
    })

    test('Renders the title as an h3 by default', () => {
      render(<SidebarHeading title="Title" />)

      expect(screen.getByRole('heading', {name: 'Title', level: 3})).toBeInTheDocument()
    })

    describe('When there is a count', () => {
      test('Renders the count', () => {
        render(<SidebarHeading title="Title" count={5} />)

        expect(screen.getByText('(5)')).toBeInTheDocument()
      })
    })

    describe('When there is an html tag', () => {
      test('Renders the title as the specified html tag', () => {
        render(<SidebarHeading title="Title" htmlTag={'h2'} />)

        expect(screen.getByRole('heading', {name: 'Title', level: 2})).toBeInTheDocument()
      })
    })
  })

  describe('When there is a link', () => {
    test('Renders the link', () => {
      render(<SidebarHeading title="Title" link="www.link.com" />)

      expect(screen.getByRole('link')).toHaveAttribute('href', 'www.link.com')
    })

    test('Renders the title as an h3 by default', () => {
      render(<SidebarHeading title="Title" link="www.link.com" />)

      expect(screen.getByRole('heading', {name: 'Title', level: 3})).toBeInTheDocument()
    })

    describe('When there is a count', () => {
      test('Renders the count', () => {
        render(<SidebarHeading title="Title" count={5} link="www.link.com" />)

        expect(screen.getByText('(5)')).toBeInTheDocument()
      })
    })

    describe('When there is an html tag', () => {
      test('Renders the title as the specified html tag', () => {
        render(<SidebarHeading title="Title" htmlTag={'h2'} link="www.link.com" />)

        expect(screen.getByRole('heading', {name: 'Title', level: 2})).toBeInTheDocument()
      })
    })
  })
})
