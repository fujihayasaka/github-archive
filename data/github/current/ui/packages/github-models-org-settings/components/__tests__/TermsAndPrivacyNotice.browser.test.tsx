import {describe, it, expect} from '@github-ui/tests'
import {screen, render} from '@testing-library/react'
import {privacyStatementLink, productTermsLink} from '@github-ui/github-models/constants'
import {TermsAndPrivacyNotice} from '../TermsAndPrivacyNotice'
import {githubPrereleaseTermsLink} from '../../constants'

describe('TermsAndPrivacyNotice', () => {
  it('renders', () => {
    render(<TermsAndPrivacyNotice />)

    const termsLink = screen.getByRole('link', {name: 'Product Terms'})
    expect(termsLink).toBeInTheDocument()
    expect(termsLink).toHaveAttribute('href', productTermsLink)
    const msftPrivLink = screen.getByRole('link', {name: 'Privacy Statement'})
    expect(msftPrivLink).toBeInTheDocument()
    expect(msftPrivLink).toHaveAttribute('href', privacyStatementLink)
    const ghPrivLink = screen.getByRole('link', {name: 'GitHub Pre-release terms'})
    expect(ghPrivLink).toBeInTheDocument()
    expect(ghPrivLink).toHaveAttribute('href', githubPrereleaseTermsLink)
  })
})
