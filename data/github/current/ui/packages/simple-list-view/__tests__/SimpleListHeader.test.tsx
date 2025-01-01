import {render, screen} from '@testing-library/react'

import {SimpleListHeader} from '../components/SimpleListHeader/SimpleListHeader'
import {SimpleListView} from '../components/SimpleListView'

describe('SimpleListHeader', () => {
  it('should render the Header component', () => {
    render(
      <SimpleListView>
        <SimpleListHeader>
          <SimpleListHeader.Title headingLevel="h3">Settings</SimpleListHeader.Title>
          <SimpleListHeader.Metadata href="#">View all</SimpleListHeader.Metadata>
        </SimpleListHeader>
      </SimpleListView>,
    )

    expect(screen.getByRole('heading', {name: 'Settings'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'View all'})).toBeInTheDocument()
  })

  describe('SimpleListHeader.Title', () => {
    it('should have the correct heading level', () => {
      render(
        <SimpleListView>
          <SimpleListHeader.Title headingLevel="h3" />
        </SimpleListView>,
      )

      expect(screen.getByRole('heading', {level: 3})).toBeInTheDocument()
    })

    it('should have the correct class name', () => {
      render(
        <SimpleListView>
          <SimpleListHeader.Title headingLevel="h3" className="title-class" />
        </SimpleListView>,
      )

      expect(screen.getByRole('heading')).toHaveClass('title-class')
    })
  })

  describe('SimpleListHeader.Metadata', () => {
    it('should render as a link', () => {
      render(
        <SimpleListView>
          <SimpleListHeader.Metadata href="https://github.com">Link</SimpleListHeader.Metadata>
        </SimpleListView>,
      )
      expect(screen.getByRole('link')).toBeInTheDocument()
    })

    it('should have the correct class name', () => {
      render(
        <SimpleListView>
          <SimpleListHeader.Metadata className="metadata-class">Class</SimpleListHeader.Metadata>
        </SimpleListView>,
      )

      expect(screen.getByText('Class')).toHaveClass('metadata-class')
    })

    it('should have the correct href', () => {
      render(
        <SimpleListView>
          <SimpleListHeader.Metadata href="https://github.com">Link</SimpleListHeader.Metadata>
        </SimpleListView>,
      )
      expect(screen.getByRole('link')).toHaveAttribute('href', 'https://github.com')
    })

    it('should render as a button', () => {
      render(
        <SimpleListView>
          <SimpleListHeader.Metadata onClick={jest.fn()}>Button</SimpleListHeader.Metadata>
        </SimpleListView>,
      )
      expect(screen.getByRole('button')).toBeInTheDocument()
    })

    it('should render as text', () => {
      render(
        <SimpleListView>
          <SimpleListHeader.Metadata>Div</SimpleListHeader.Metadata>
        </SimpleListView>,
      )
      expect(screen.getByText('Div')).toBeInTheDocument()
    })
  })
})
