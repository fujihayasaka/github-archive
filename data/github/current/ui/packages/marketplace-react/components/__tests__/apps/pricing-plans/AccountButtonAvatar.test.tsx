import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {AccountButtonAvatar} from '../../../apps/pricing-plans/AccountButtonAvatar'
import {mockPlanInfo} from '../../../../test-utils/mock-data'

const currentUserWithImage = {
  displayLogin: 'monalisa',
  image: 'https://github/monalisa.png',
  hasExtensibilityAccess: true,
  installedForOrg: false,
}
const currentUserWithoutImage = {
  displayLogin: 'monalisa',
  image: '',
  hasExtensibilityAccess: true,
  installedForOrg: false,
}
const organizationWithImage = {
  displayLogin: 'GitHub',
  image: 'https://github/github.png',
  hasExtensibilityAccess: true,
  isEnterpriseOwned: true,
  installedForOrg: false,
}
const organizationWithoutImage = {
  displayLogin: 'GitHub',
  image: '',
  hasExtensibilityAccess: true,
  isEnterpriseOwned: true,
  installedForOrg: false,
}
const nonMatchingOrganization = {
  displayLogin: 'SomethingElse',
  image: 'https://github/somethingelse.png',
  hasExtensibilityAccess: true,
  isEnterpriseOwned: false,
  installedForOrg: false,
}

describe('AccountButtonAvatar', () => {
  describe('when there is no account', () => {
    test('does not render anything', () => {
      const {container} = render(<AccountButtonAvatar planInfo={mockPlanInfo()} account={undefined} />)

      expect(container).toBeEmptyDOMElement()
    })
  })

  describe('when there is an account', () => {
    describe('when there is a current user', () => {
      describe('when the account matches the current user', () => {
        test('renders the current user avatar if it has an image', () => {
          render(
            <AccountButtonAvatar
              planInfo={mockPlanInfo({
                currentUser: currentUserWithImage,
              })}
              account={'monalisa'}
            />,
          )

          expect(screen.getByTestId('user-account-avatar')).toHaveAttribute(
            'src',
            expect.stringContaining('https://github/monalisa.png'),
          )
        })

        test('does not render anything if the current user does not have an image', () => {
          const {container} = render(
            <AccountButtonAvatar
              planInfo={mockPlanInfo({
                currentUser: currentUserWithoutImage,
              })}
              account={'monalisa'}
            />,
          )

          expect(container).toBeEmptyDOMElement()
        })
      })

      describe('when the account does not match the current user', () => {
        describe('when the account matches an organization', () => {
          test('renders the organization avatar if it has an image', () => {
            render(
              <AccountButtonAvatar
                planInfo={mockPlanInfo({
                  currentUser: currentUserWithImage,
                  organizations: [organizationWithImage, nonMatchingOrganization],
                })}
                account={'GitHub'}
              />,
            )

            expect(screen.getByTestId('org-account-avatar')).toHaveAttribute(
              'src',
              expect.stringContaining('https://github/github.png'),
            )
          })

          test('does not render anything if the organization does not have an image', () => {
            const {container} = render(
              <AccountButtonAvatar
                planInfo={mockPlanInfo({
                  currentUser: currentUserWithImage,
                  organizations: [organizationWithoutImage, nonMatchingOrganization],
                })}
                account={'GitHub'}
              />,
            )

            expect(container).toBeEmptyDOMElement()
          })
        })

        describe('when the account does not match an organization', () => {
          test('does not render anything', () => {
            const {container} = render(
              <AccountButtonAvatar
                planInfo={mockPlanInfo({
                  currentUser: currentUserWithImage,
                  organizations: [organizationWithImage, nonMatchingOrganization],
                })}
                account={'UltimateOctocat'}
              />,
            )

            expect(container).toBeEmptyDOMElement()
          })
        })
      })
    })

    describe('when there is no current user', () => {
      describe('when the account matches an organization', () => {
        test('renders the organization avatar if it has an image', () => {
          render(
            <AccountButtonAvatar
              planInfo={mockPlanInfo({
                currentUser: undefined,
                organizations: [organizationWithImage, nonMatchingOrganization],
              })}
              account={'GitHub'}
            />,
          )

          expect(screen.getByTestId('org-account-avatar')).toHaveAttribute(
            'src',
            expect.stringContaining('https://github/github.png'),
          )
        })

        test('does not render anything if the organization does not have an image', () => {
          const {container} = render(
            <AccountButtonAvatar
              planInfo={mockPlanInfo({
                currentUser: undefined,
                organizations: [organizationWithoutImage, nonMatchingOrganization],
              })}
              account={'GitHub'}
            />,
          )

          expect(container).toBeEmptyDOMElement()
        })
      })

      describe('when the account does not match an organization', () => {
        test('does not render anything', () => {
          const {container} = render(
            <AccountButtonAvatar
              planInfo={mockPlanInfo({
                currentUser: undefined,
                organizations: [organizationWithImage, nonMatchingOrganization],
              })}
              account={'UltimateOctocat'}
            />,
          )

          expect(container).toBeEmptyDOMElement()
        })
      })
    })
  })
})
