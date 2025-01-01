import {Link} from '@primer/react'
import {privacyStatementLink, productTermsLink} from '@github-ui/github-models/constants'
import {githubPrivacyStatementLink} from '../constants'

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
      </Link>{' '}
      and the{' '}
      <Link inline href={githubPrivacyStatementLink}>
        GitHub Privacy Statement
      </Link>
      . Not intended for production/sensitive data.
    </p>
  )
}
