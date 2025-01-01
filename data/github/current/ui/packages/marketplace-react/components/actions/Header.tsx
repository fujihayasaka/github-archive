import type {ActionListing} from '@github-ui/marketplace-common'
import {OverviewHeader} from '../OverviewHeader'
import {About} from './About'
import {Tags} from '../sidebar-shared/Tags'
import type {Repository, ReleaseData, StarData} from '../../types'
import {ReleaseBanner} from './ReleaseBanner'
import {Stack} from '@primer/react'
import {VersionButton} from './VersionButton'
import {StarButton} from './StarButton'
import {VerifiedOwner} from '../sidebar-shared/VerifiedOwner'

interface HeaderProps {
  action: ActionListing
  repository: Repository
  releaseData: ReleaseData
  loggedIn: boolean
  starData: StarData
}

export function Header(props: HeaderProps) {
  const {action, repository, releaseData, loggedIn, starData} = props
  const {selectedRelease, latestRelease} = releaseData
  const {isVerifiedOwner} = action

  return (
    <OverviewHeader
      listing={action}
      loggedIn={loggedIn}
      banner={<ReleaseBanner selectedRelease={selectedRelease} latestRelease={latestRelease} action={action} />}
      listingDetails={<About action={action} repository={repository} releaseData={releaseData} />}
      additionalDetails={
        <>
          <Tags tags={action.categories} type="actions" />
          <VerifiedOwner isVerifiedOwner={isVerifiedOwner} pageType="actions" />
        </>
      }
      callToAction={
        <Stack
          gap={'condensed'}
          direction={{narrow: 'vertical', regular: 'horizontal'}}
          className={'width-full width-md-auto'}
        >
          <StarButton repository={repository} action={action} loggedIn={loggedIn} starData={starData} />
          <VersionButton releaseData={releaseData} action={action} repository={repository} />
        </Stack>
      }
    />
  )
}
