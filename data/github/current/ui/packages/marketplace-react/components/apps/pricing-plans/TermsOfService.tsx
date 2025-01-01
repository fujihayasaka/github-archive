import {useMemo, useState} from 'react'
import {Link, RelativeTime} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import type {PlanInfo, Plan} from '../../../types'
import type {AppListing} from '@github-ui/marketplace-common'

type Props = {
  planInfo: PlanInfo
  plan?: Plan
  listing: AppListing
}

export function TermsOfService({planInfo, plan, listing}: Props) {
  const agreement = planInfo.endUserAgreement
  const [agreementDialogOpen, setAgreementDialogOpen] = useState(false)
  const textClassName = 'text-center text-wrap-balance f6 fgColor-muted'

  const buttonText = useMemo(() => {
    return `Set up with ${listing.name}`
  }, [listing.name])

  return (
    <>
      {plan && plan.directBilling && planInfo.isLoggedIn && agreement ? (
        <p className={textClassName} data-testid="terms-of-service">
          {listing.tosUrl ? (
            <>
              By clicking “{buttonText},” you are agreeing to{' '}
              {!agreement.userSignedAt && (
                <>
                  the{' '}
                  <Link as="button" inline onClick={() => setAgreementDialogOpen(true)}>
                    {agreement.name}
                  </Link>
                  ,
                </>
              )}
              {listing.name}’s{' '}
              <Link target="_blank" rel="noopener noreferrer" href={listing.tosUrl} inline>
                Terms of Service
              </Link>{' '}
              and the{' '}
              <Link target="_blank" rel="noopener noreferrer" href={listing.privacyPolicyUrl} inline>
                Privacy Policy
              </Link>
              .
            </>
          ) : (
            <>
              By clicking {buttonText}, you agree to{' '}
              {!agreement.userSignedAt && (
                <>
                  the{' '}
                  <Link as="button" inline onClick={() => setAgreementDialogOpen(true)}>
                    {agreement.name}
                  </Link>
                  , and{' '}
                </>
              )}
              {listing.name}’s{' '}
              <Link target="_blank" rel="noopener noreferrer" href={listing.privacyPolicyUrl} inline>
                Privacy Policy
              </Link>
              .
            </>
          )}

          {agreement.userSignedAt && (
            <>
              {' '}
              You previously agreed to the{' '}
              <Link as="button" inline onClick={() => setAgreementDialogOpen(true)}>
                {agreement.name}
              </Link>
              .
            </>
          )}
          <Dialog isOpen={agreementDialogOpen} onDismiss={() => setAgreementDialogOpen(false)} aria-labelledby="header">
            <div data-testid="inner">
              <Dialog.Header id="header">{`GitHub ${agreement.name} ${agreement.version}`}</Dialog.Header>
              <SafeHTMLBox html={agreement.html as SafeHTMLString} className="p-3" />
              {agreement.userSignedAt && (
                <div className="p-3 border-top">
                  You agreed to these terms <RelativeTime date={new Date(agreement.userSignedAt)} />
                </div>
              )}
            </div>
          </Dialog>
        </p>
      ) : (
        <>
          {planInfo.listingByGithub ? (
            <p className={textClassName}>
              {listing.name} is owned and operated by GitHub{' '}
              {listing.tosUrl ? (
                <>
                  with separate{' '}
                  <Link href={listing.tosUrl} inline>
                    terms of service
                  </Link>
                  {', '}
                  <Link href={listing.privacyPolicyUrl} inline>
                    privacy policy
                  </Link>
                  ,
                </>
              ) : (
                <>
                  with separate{' '}
                  <Link href={listing.privacyPolicyUrl} inline>
                    privacy policy
                  </Link>
                </>
              )}{' '}
              and{' '}
              {listing.supportEmail ? (
                <>
                  <Link href={`mailto:${listing.supportEmail}`} inline>
                    support contact
                  </Link>
                  .
                </>
              ) : (
                <>
                  <Link href={listing.supportUrl} inline>
                    support documentation
                  </Link>
                  .
                </>
              )}
            </p>
          ) : (
            <p className={textClassName}>
              {listing.name} is provided by a third-party and is governed by{' '}
              {listing.tosUrl ? (
                <>
                  separate{' '}
                  <Link href={listing.tosUrl} inline>
                    terms of service
                  </Link>
                  {', '}
                  <Link href={listing.privacyPolicyUrl} inline>
                    privacy policy
                  </Link>
                  ,
                </>
              ) : (
                <>
                  separate{' '}
                  <Link href={listing.privacyPolicyUrl} inline>
                    privacy policy
                  </Link>
                </>
              )}{' '}
              and{' '}
              {listing.supportEmail ? (
                <>
                  <Link href={`mailto:${listing.supportEmail}`} inline>
                    support contact
                  </Link>
                  .
                </>
              ) : (
                <Link href={listing.supportUrl} inline>
                  support documentation
                </Link>
              )}
            </p>
          )}
        </>
      )}
    </>
  )
}
