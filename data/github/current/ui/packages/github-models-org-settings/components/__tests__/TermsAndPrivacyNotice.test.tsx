import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {privacyStatementLink, productTermsLink} from '@github-ui/github-models/constants'
import {TermsAndPrivacyNotice} from '../TermsAndPrivacyNotice'
import {githubPrivacyStatementLink} from '../../constants'

describe('TermsAndPrivacyNotice', () => {
  it('renders', () => {
    render(<TermsAndPrivacyNotice />)

    const termsLink = screen.getByRole('link', {name: 'Product Terms'})
    expect(termsLink).toBeInTheDocument()
    expect(termsLink).toHaveAttribute('href', productTermsLink)
    const msftPrivLink = screen.getByRole('link', {name: 'Privacy Statement'})
    expect(msftPrivLink).toBeInTheDocument()
    expect(msftPrivLink).toHaveAttribute('href', privacyStatementLink)
    const ghPrivLink = screen.getByRole('link', {name: 'GitHub Privacy Statement'})
    expect(ghPrivLink).toBeInTheDocument()
    expect(ghPrivLink).toHaveAttribute('href', githubPrivacyStatementLink)
  })
})
