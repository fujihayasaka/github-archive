import {ThirdPartyStatement} from '../../actions/ThirdPartyStatement'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('ThirdPartyStatement', () => {
  describe('When isThirdParty is false', () => {
    describe('When name is not present', () => {
      test('Does not render', () => {
        render(<ThirdPartyStatement isThirdParty={false} name="" />)

        expect(screen.queryByTestId('third-party-statement')).not.toBeInTheDocument()
      })
    })

    describe('When name is present', () => {
      test('Does not render', () => {
        render(<ThirdPartyStatement isThirdParty={false} name={'test'} />)

        expect(screen.queryByTestId('third-party-statement')).not.toBeInTheDocument()
      })
    })
  })

  describe('When isThirdParty is true', () => {
    describe('When name is not present', () => {
      test('Does not render', () => {
        render(<ThirdPartyStatement isThirdParty name="" />)

        expect(screen.queryByTestId('third-party-statement')).not.toBeInTheDocument()
      })
    })

    describe('When name is present', () => {
      test('Renders', () => {
        render(<ThirdPartyStatement isThirdParty name={'test'} />)

        expect(screen.getByTestId('third-party-statement')).toBeInTheDocument()
      })

      test('Renders the disclaimer', () => {
        render(<ThirdPartyStatement isThirdParty name={'test'} />)

        expect(screen.getByText('test')).toBeInTheDocument()
        expect(
          screen.getByText(
            'is not certified by GitHub. It is provided by a third-party and is governed by separate terms of service, privacy policy, and support documentation.',
          ),
        ).toBeInTheDocument()
      })
    })
  })
})
