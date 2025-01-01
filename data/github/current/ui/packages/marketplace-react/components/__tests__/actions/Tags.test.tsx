import {Tags} from '../../actions/Tags'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('Tags', () => {
  describe('When no tags are provided', () => {
    it('Does not render', () => {
      render(<Tags tags={[]} />)

      expect(screen.queryByTestId('tags')).not.toBeInTheDocument()
    })
  })

  describe('When tags are provided', () => {
    it('Renders', () => {
      render(
        <Tags
          tags={[
            {name: 'tag-1', slug: 'tag-1'},
            {name: 'tag-2', slug: 'tag-2'},
          ]}
        />,
      )

      expect(screen.getByTestId('tags')).toBeInTheDocument()
    })

    it('Renders the heading', () => {
      render(
        <Tags
          tags={[
            {name: 'tag-1', slug: 'tag-1'},
            {name: 'tag-2', slug: 'tag-2'},
          ]}
        />,
      )

      expect(screen.getByRole('heading', {name: 'Tags', level: 2})).toBeInTheDocument()
    })

    it('Renders the tags', () => {
      render(
        <Tags
          tags={[
            {name: 'tag-1', slug: 'tag-1'},
            {name: 'tag-2', slug: 'tag-2'},
          ]}
        />,
      )

      expect(screen.getByRole('link', {name: 'tag-1'})).toHaveAttribute(
        'href',
        '/marketplace?type=actions&category=tag-1',
      )
      expect(screen.getByRole('link', {name: 'tag-2'})).toHaveAttribute(
        'href',
        '/marketplace?type=actions&category=tag-2',
      )
    })
  })
})
