import {useState} from 'react'
import {IncludeFragment} from '@github-ui/include-fragment-react'
import {testIdProps} from '@github-ui/test-id-props'
import {Heading, Link, Spinner} from '@primer/react'
import type {DocsLinks, FormData, SponsorableData, SponsorsListingData} from './SignupForm'
import {SignupForm} from './SignupForm'

import styles from './SponsorsSignup.module.css'

export interface SponsorsSignupProps {
  formData: FormData
  sponsorableData: SponsorableData
  sponsorsListingData?: SponsorsListingData
  docsLinks: DocsLinks
}

export function SponsorsSignup({formData, sponsorableData, sponsorsListingData, docsLinks}: SponsorsSignupProps) {
  const [sponsorsListingDataState, setSponsorsListingDataState] = useState<SponsorsListingData | undefined>(
    sponsorsListingData,
  )

  return (
    <div className="container-sm p-responsive mt-7">
      <div className="d-flex flex-column flex-items-center mb-3">
        <Heading as="h1" className={styles.Heading}>
          Get Sponsored
        </Heading>
        <span className={styles.Text}>
          Launch a{' '}
          <Link href={docsLinks.about} inline {...testIdProps('sponsors-help-docs')}>
            GitHub Sponsors profile
          </Link>{' '}
          and start receiving funding.
        </span>
      </div>
      {sponsorsListingDataState === undefined || sponsorsListingDataState?.isWaitlisted ? (
        <SignupForm
          formData={formData}
          sponsorableData={sponsorableData}
          sponsorsListingData={sponsorsListingDataState}
          docsLinks={docsLinks}
          setSponsorsListingData={setSponsorsListingDataState}
        />
      ) : (
        <IncludeFragment src={sponsorsListingDataState.signupStatusPartialPath}>
          <div className="d-flex flex-column flex-items-center">
            <Spinner size="medium" aria-label="Loading sign-up status" />
          </div>
        </IncludeFragment>
      )}
    </div>
  )
}
