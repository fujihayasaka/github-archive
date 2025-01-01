import {Link} from '@primer/react'
import {privacyStatementLink, productTermsLink} from '@github-ui/github-models/constants'
import {githubPrereleaseTermsLink} from '../constants'

export function TermsAndPrivacyNotice() {
  return (
    <p className="fgColor-muted mt-3">
      If enabled, users can send code and interact with third-party AI models hosted on Microsoft Azure and subject to
      Microsoft&rsquo;s{' '}
      <Link inline href={productTermsLink}>
        Product Terms
      </Link>{' '}
      &amp;{' '}
      <Link inline href={privacyStatementLink}>
        Privacy Statement
      </Link>
      . Use of Models is subject to the{' '}
      <Link inline href={githubPrereleaseTermsLink}>
        GitHub Pre-release terms
      </Link>
      .
    </p>
  )
}
