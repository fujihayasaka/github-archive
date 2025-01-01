import {OverviewHeader} from '../OverviewHeader'
import {About} from './About'
import {CallToAction} from './CallToAction'
import {HeaderActionMenu} from './HeaderActionMenu'
import {Stack, useResponsiveValue} from '@primer/react'
import styles from '../../marketplace.module.css'
import type {AppListing} from '@github-ui/marketplace-common'
import type {PlanInfo} from '../../types'
import {VerifiedOwner} from '../sidebar-shared/VerifiedOwner'
import {WorksWith} from './sidebar/WorksWith'
import {PlanInfo as HeaderPlanInfo} from './sidebar/PlanInfo'
import {Tags} from '../sidebar-shared/Tags'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import InstallUnavailableBanner from './InstallUnavailableBanner'

interface HeaderProps {
  app: AppListing
  planInfo: PlanInfo
  userCanEdit: boolean
}

export function Header(props: HeaderProps) {
  const {app, planInfo, userCanEdit} = props

  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const marketplaceFreeInstallFlag = useFeatureFlag('marketplace_free_install')
  const renderInstallUnavailableBanner = marketplaceFreeInstallFlag && app.copilotApp && isMobile

  return (
    <OverviewHeader
      listing={app}
      listingDetails={<About app={app} />}
      additionalDetails={
        <>
          <Tags tags={app.categories} type="apps" />
          <VerifiedOwner isVerifiedOwner={app.isVerifiedOwner} pageType="apps" />
          <WorksWith isCopilotApp={app.copilotApp} />
          <HeaderPlanInfo planInfo={planInfo} isCopilotApp={app.copilotApp} />
        </>
      }
      callToAction={
        <>
          {renderInstallUnavailableBanner && <InstallUnavailableBanner planInfo={planInfo} />}
          <Stack
            gap={'condensed'}
            direction={'horizontal'}
            className={`width-full width-md-auto ${styles['marketplace-cta-buttons-container']}`}
          >
            <CallToAction planInfo={planInfo} app={app} />
            <HeaderActionMenu app={app} planInfo={planInfo} userCanEdit={userCanEdit} />
          </Stack>
        </>
      }
    />
  )
}
