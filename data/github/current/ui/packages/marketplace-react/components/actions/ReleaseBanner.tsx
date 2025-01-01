import {Banner} from '@primer/react/experimental'
import {marketplaceActionPath} from '@github-ui/paths'
import {Link} from '@primer/react'
import type {Release} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'

interface ReleaseBannerProps {
  action: ActionListing
  selectedRelease?: Release
  latestRelease: Release
}

export function ReleaseBanner(props: ReleaseBannerProps) {
  const {action, selectedRelease, latestRelease} = props
  const {slug} = action
  const isOnOldRelease = selectedRelease && selectedRelease.tagName !== latestRelease.tagName

  return (
    <>
      {isOnOldRelease && slug && (
        <Banner
          variant={'warning'}
          hideTitle
          title={'Warning'}
          description={
            <>
              You&#39;re viewing an older version of this GitHub Action. Do you want to see the{' '}
              <Link href={marketplaceActionPath({slug})} inline>
                latest version
              </Link>{' '}
              instead?
            </>
          }
        />
      )}
    </>
  )
}
