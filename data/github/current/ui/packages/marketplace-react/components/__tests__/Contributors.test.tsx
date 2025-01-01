import {Contributors} from '../Contributors'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockRepository} from '../../test-utils/mock-data'
import {userHovercardPath, repoContributorsPath, ownerPath} from '@github-ui/paths'

describe('Contributors', () => {
  describe('When there are no contributors', () => {
    test('Does not render', () => {
      const repository = mockRepository({contributorsCount: 0})

      render(<Contributors repository={repository} />)

      expect(screen.queryByTestId('contributors')).not.toBeInTheDocument()
    })
  })

  describe('When the repository does not have an owner', () => {
    test('Does not render', () => {
      const repository = mockRepository({contributorsCount: 5, owner: ''})

      render(<Contributors repository={repository} />)

      expect(screen.queryByTestId('contributors')).not.toBeInTheDocument()
    })
  })

  describe('When the repository does not have a name', () => {
    test('Does not render', () => {
      const repository = mockRepository({contributorsCount: 5, name: ''})

      render(<Contributors repository={repository} />)

      expect(screen.queryByTestId('contributors')).not.toBeInTheDocument()
    })
  })

  describe('When there are contributors and the repository has an owner and name', () => {
    test('Renders', () => {
      const repository = mockRepository({contributorsCount: 5})

      render(<Contributors repository={repository} />)

      expect(screen.getByTestId('contributors')).toBeInTheDocument()
    })

    test('Renders the heading with the correct count and link to contributors', () => {
      const repository = mockRepository({contributorsCount: 5, owner: 'owner', name: 'repo'})

      render(<Contributors repository={repository} />)

      expect(screen.getByRole('link', {name: 'Contributors (5)'})).toHaveAttribute(
        'href',
        repoContributorsPath({ownerLogin: 'owner', name: 'repo'}),
      )
    })

    test('Renders the top contributors', () => {
      const repository = mockRepository({
        topContributorsData: [
          {
            src: 'https://avatars.githubusercontent.com/u/1?v=4',
            alt: 'octocat',
            displayLogin: 'octocat',
          },
          {
            src: 'https://avatars.githubusercontent.com/u/2?v=4',
            alt: 'monalisa',
            displayLogin: 'monalisa',
          },
        ],
      })

      render(<Contributors repository={repository} />)

      expect(screen.getByRole('link', {name: 'octocat'})).toHaveAttribute('href', ownerPath({owner: 'octocat'}))
      expect(screen.getByRole('img', {name: 'octocat'})).toHaveAttribute(
        'data-hovercard-url',
        userHovercardPath({owner: 'octocat'}),
      )
      expect(screen.getByRole('link', {name: 'monalisa'})).toHaveAttribute('href', ownerPath({owner: 'monalisa'}))
      expect(screen.getByRole('img', {name: 'monalisa'})).toHaveAttribute(
        'data-hovercard-url',
        userHovercardPath({owner: 'monalisa'}),
      )
    })

    describe('When there are more than just the top contributors', () => {
      test('Renders the remaining contributors link', () => {
        const repository = mockRepository({
          contributorsCount: 5,
          topContributorsData: [
            {
              src: 'https://avatars.githubusercontent.com/u/1?v=4',
              alt: 'octocat',
              displayLogin: 'octocat',
            },
            {
              src: 'https://avatars.githubusercontent.com/u/2?v=4',
              alt: 'monalisa',
              displayLogin: 'monalisa',
            },
          ],
          owner: 'owner',
          name: 'repo',
        })

        render(<Contributors repository={repository} />)

        expect(screen.getByRole('link', {name: '+ 3 contributors'})).toHaveAttribute(
          'href',
          repoContributorsPath({ownerLogin: 'owner', name: 'repo'}),
        )
      })
    })

    describe('When there are no more contributors than the top contributors', () => {
      test('Does not render the remaining contributors link', () => {
        const repository = mockRepository({
          contributorsCount: 2,
          topContributorsData: [
            {
              src: 'https://avatars.githubusercontent.com/u/1?v=4',
              alt: 'octocat',
              displayLogin: 'octocat',
            },
            {
              src: 'https://avatars.githubusercontent.com/u/2?v=4',
              alt: 'monalisa',
              displayLogin: 'monalisa',
            },
          ],
        })

        render(<Contributors repository={repository} />)

        expect(screen.queryByText(/\+/)).not.toBeInTheDocument()
      })
    })
  })
})
