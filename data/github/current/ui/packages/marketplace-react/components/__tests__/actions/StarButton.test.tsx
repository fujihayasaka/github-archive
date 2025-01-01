import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {StarButton} from '../../actions/StarButton'
import {render} from '@github-ui/react-core/test-utils'
import {screen, act, waitFor} from '@testing-library/react'
import {mockRepository, mockStarData} from '../../../test-utils/mock-data'
import {marketplaceActionPath} from '@github-ui/paths'
import {verifiedFetch} from '@github-ui/verified-fetch'

// Mock the verifiedFetch function
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

describe('StarButton', () => {
  const mockedVerifiedFetch = verifiedFetch as jest.MockedFunction<typeof verifiedFetch>

  describe('When the user is not logged in', () => {
    it('Renders the star button as a link to login', () => {
      render(
        <StarButton
          action={mockActionListing({stars: 10, slug: 'slug'})}
          repository={mockRepository()}
          loggedIn={false}
          starData={mockStarData()}
        />,
      )

      expect(screen.getByTestId('star-button')).toBeInTheDocument()
      expect(screen.getByRole('link', {name: 'Star (10)'})).toHaveAttribute(
        'href',
        `/login?return_to=${encodeURIComponent(marketplaceActionPath({slug: 'slug'}))}`,
      )
    })

    it('Renders a tooltip telling the user to login', () => {
      render(
        <StarButton
          action={mockActionListing({stars: 10, slug: 'slug'})}
          repository={mockRepository()}
          loggedIn={false}
          starData={mockStarData()}
        />,
      )

      expect(screen.getByText('You must be signed in to star a repository')).toBeInTheDocument()
    })
  })

  describe('When the user is logged in', () => {
    describe('When the user is able to star the repository', () => {
      describe('When the repository is starred by the user', () => {
        it('Renders the star button in the starred state', () => {
          render(
            <StarButton
              action={mockActionListing({stars: 10, slug: 'slug'})}
              repository={mockRepository()}
              loggedIn
              starData={mockStarData({starredByCurrentUser: true})}
            />,
          )

          expect(screen.getByTestId('star-button')).toBeInTheDocument()
          expect(screen.getByRole('button', {name: 'Unstar this repository (10)'})).toBeInTheDocument()
          expect(screen.getByText('Starred')).toBeInTheDocument()
          expect(screen.getByText('(10)')).toBeInTheDocument()
        })

        it('Handles the user unstarring the repository', async () => {
          mockedVerifiedFetch.mockResolvedValue({ok: true} as Response)

          render(
            <StarButton
              action={mockActionListing({stars: 10, slug: 'slug'})}
              repository={mockRepository()}
              loggedIn
              starData={mockStarData({starredByCurrentUser: true})}
            />,
          )

          const button = screen.getByRole('button', {name: 'Unstar this repository (10)'})
          act(() => button.click())

          await waitFor(() => {
            expect(screen.getByRole('button', {name: 'Star this repository (9)'})).toBeInTheDocument()
          })
          expect(screen.getByText('Star')).toBeInTheDocument()
          expect(screen.getByText('(9)')).toBeInTheDocument()
        })

        describe('When the request to unstar the repository fails', () => {
          it('Leaves the button in the starred state', async () => {
            mockedVerifiedFetch.mockResolvedValue({ok: false} as Response)

            render(
              <StarButton
                action={mockActionListing({stars: 10, slug: 'slug'})}
                repository={mockRepository()}
                loggedIn
                starData={mockStarData({starredByCurrentUser: true})}
              />,
            )

            const button = screen.getByRole('button', {name: 'Unstar this repository (10)'})
            act(() => button.click())

            await waitFor(() => {
              expect(screen.getByRole('button', {name: 'Unstar this repository (10)'})).toBeInTheDocument()
            })
            expect(screen.getByText('Starred')).toBeInTheDocument()
            expect(screen.getByText('(10)')).toBeInTheDocument()
          })
        })
      })

      describe('When the repository is not starred by the user', () => {
        it('Renders the star button in the unstarred state', () => {
          render(
            <StarButton
              action={mockActionListing({stars: 10, slug: 'slug'})}
              repository={mockRepository()}
              loggedIn
              starData={mockStarData({starredByCurrentUser: false})}
            />,
          )

          expect(screen.getByTestId('star-button')).toBeInTheDocument()
          expect(screen.getByRole('button', {name: 'Star this repository (10)'})).toBeInTheDocument()
          expect(screen.getByText('Star')).toBeInTheDocument()
          expect(screen.getByText('(10)')).toBeInTheDocument()
        })

        it('Handles the user starring the repository', async () => {
          mockedVerifiedFetch.mockResolvedValue({ok: true} as Response)

          render(
            <StarButton
              action={mockActionListing({stars: 10, slug: 'slug'})}
              repository={mockRepository()}
              loggedIn
              starData={mockStarData({starredByCurrentUser: false})}
            />,
          )

          const button = screen.getByRole('button', {name: 'Star this repository (10)'})
          act(() => button.click())

          await waitFor(() => {
            expect(screen.getByRole('button', {name: 'Unstar this repository (11)'})).toBeInTheDocument()
          })
          expect(screen.getByText('Starred')).toBeInTheDocument()
          expect(screen.getByText('(11)')).toBeInTheDocument()
        })

        describe('When the request to star the repository fails', () => {
          it('Leaves the button in the unstarred state', async () => {
            mockedVerifiedFetch.mockResolvedValue({ok: false} as Response)

            render(
              <StarButton
                action={mockActionListing({stars: 10, slug: 'slug'})}
                repository={mockRepository()}
                loggedIn
                starData={mockStarData({starredByCurrentUser: false})}
              />,
            )

            const button = screen.getByRole('button', {name: 'Star this repository (10)'})
            act(() => button.click())

            await waitFor(() => {
              expect(screen.getByRole('button', {name: 'Star this repository (10)'})).toBeInTheDocument()
            })
            expect(screen.getByText('Star')).toBeInTheDocument()
            expect(screen.getByText('(10)')).toBeInTheDocument()
          })
        })
      })
    })

    describe('When the user is not able to star the repository', () => {
      describe('When the repository is already starred by the user', () => {
        it('Renders the star button in the starred state', () => {
          render(
            <StarButton
              action={mockActionListing({stars: 10, slug: 'slug'})}
              repository={mockRepository()}
              loggedIn
              starData={mockStarData({starredByCurrentUser: true, currentUserAbleToStar: false})}
            />,
          )

          expect(screen.getByTestId('star-button')).toBeInTheDocument()
          expect(screen.getByRole('button', {name: 'Unstar this repository (10)'})).toBeInTheDocument()
          expect(screen.getByText('Starred')).toBeInTheDocument()
          expect(screen.getByText('(10)')).toBeInTheDocument()
        })

        it('Handles unstarring the repository and then shows the disabled star button if the user unstars the repository', async () => {
          mockedVerifiedFetch.mockResolvedValue({ok: true} as Response)

          render(
            <StarButton
              action={mockActionListing({stars: 10, slug: 'slug'})}
              repository={mockRepository()}
              loggedIn
              starData={mockStarData({starredByCurrentUser: true, currentUserAbleToStar: false})}
            />,
          )

          const button = screen.getByRole('button', {name: 'Unstar this repository (10)'})
          act(() => button.click())

          await waitFor(() => {
            expect(screen.getByTestId('star-button')).toHaveAttribute('data-inactive', 'true')
          })
          expect(screen.getByText('Star')).toBeInTheDocument()
          expect(screen.getByText('(9)')).toBeInTheDocument()
        })
      })

      describe('When the repository is not already starred by the user', () => {
        it('Renders the disabled star button', () => {
          render(
            <StarButton
              action={mockActionListing({stars: 10, slug: 'slug'})}
              repository={mockRepository()}
              loggedIn
              starData={mockStarData({starredByCurrentUser: false, currentUserAbleToStar: false})}
            />,
          )

          expect(screen.getByTestId('star-button')).toHaveAttribute('data-inactive', 'true')
          expect(screen.getByText('Star')).toBeInTheDocument()
          expect(screen.getByText('(10)')).toBeInTheDocument()
        })

        describe('When the current user has an enterprise', () => {
          it('Renders tooltip telling user they cannot star', () => {
            render(
              <StarButton
                action={mockActionListing({stars: 10, slug: 'slug'})}
                repository={mockRepository()}
                loggedIn
                starData={mockStarData({
                  starredByCurrentUser: false,
                  currentUserAbleToStar: false,
                  currentUserEnterpriseName: 'Enterprise',
                })}
              />,
            )

            expect(
              screen.getByText('You cannot star repositories outside of your enterprise Enterprise'),
            ).toBeInTheDocument()
          })
        })

        describe('When the current user does not have an enterprise', () => {
          it('Renders tooltip telling user they cannot star', () => {
            render(
              <StarButton
                action={mockActionListing({stars: 10, slug: 'slug'})}
                repository={mockRepository()}
                loggedIn
                starData={mockStarData({
                  starredByCurrentUser: false,
                  currentUserAbleToStar: false,
                  currentUserEnterpriseName: '',
                })}
              />,
            )

            expect(screen.getByText("You can't star at this time")).toBeInTheDocument()
          })
        })
      })
    })
  })

  describe('When the star count is less than 1000', () => {
    it('Renders the unrounded star count', () => {
      render(
        <StarButton
          action={mockActionListing({stars: 999})}
          repository={mockRepository()}
          loggedIn
          starData={mockStarData()}
        />,
      )

      expect(screen.getByText('(999)')).toBeInTheDocument()
    })
  })

  describe('When the star count is greater than or equal to 1000', () => {
    it('Renders the rounded star count', () => {
      render(
        <StarButton
          action={mockActionListing({stars: 10599})}
          repository={mockRepository()}
          loggedIn
          starData={mockStarData()}
        />,
      )

      expect(screen.getByText('(10.6K)')).toBeInTheDocument()
    })
  })
})
