import {SafeHTMLBox} from '@github-ui/safe-html'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {Stack, UnderlineNav, useResponsiveValue} from '@primer/react'
import Screenshots from '../../components/Screenshots'
import {CopilotListingRequirement} from '../../components/CopilotListingRequirement'
import {Plans} from './pricing-plans/Plans'
import {TransparencySection} from './TransparencySection'
import type {AppListing} from '@github-ui/marketplace-common'
import type {Screenshot, PlanInfo, PermissionsData} from '../../types'
import styles from '../../marketplace.module.css'
import {Resources} from './sidebar/Resources'
import {Languages} from './sidebar/Languages'
import {BookIcon, LogIcon} from '@primer/octicons-react'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {Link, useSearchParams} from 'react-router-dom'
import InstallUnavailableBanner from './InstallUnavailableBanner'
import {TermsOfService} from './pricing-plans/TermsOfService'

interface BodyProps {
  app: AppListing
  screenshots: Screenshot[]
  planInfo: PlanInfo
  supportedLanguages: string[]
  permissionsData: PermissionsData[]
}

export function Body(props: BodyProps) {
  const {app, screenshots, planInfo, supportedLanguages, permissionsData} = props
  const isDesktop = useResponsiveValue({regular: true}, false) as boolean
  const showTransparencyInfo = useFeatureFlag('marketplace_show_transparency_info')
  const marketplaceFreeInstallFlag = useFeatureFlag('marketplace_free_install')
  const renderInstallUnavailableBanner = marketplaceFreeInstallFlag && app.copilotApp && isDesktop
  const selectedPlan = planInfo.plans.find(plan => plan.id === planInfo.selectedPlanId)

  const [searchParams] = useSearchParams()
  const tabParam = searchParams.get('tab')
  const activeTab = tabParam === 'transparency' ? 'transparency' : 'readme'

  const readmeContent = (
    <Stack gap="normal" data-testid="readme-content">
      {app.fullDescription && <SafeHTMLBox className="markdown-body" html={app.fullDescription as SafeHTMLString} />}
      {app.extendedDescription && (
        <SafeHTMLBox className="markdown-body" html={app.extendedDescription as SafeHTMLString} />
      )}
      <Screenshots screenshots={screenshots} />
    </Stack>
  )

  let content
  if (activeTab === 'transparency') {
    content = <TransparencySection app={app} permissionsData={permissionsData} />
  } else {
    content = readmeContent
  }

  return (
    <Stack gap="spacious">
      {renderInstallUnavailableBanner && <InstallUnavailableBanner planInfo={planInfo} />}
      {showTransparencyInfo ? (
        <div
          className={`${styles['marketplace-content-container']} ${styles['marketplace-content-container--no-padding']}`}
        >
          <UnderlineNav aria-label="Select a tab">
            <UnderlineNav.Item
              icon={BookIcon}
              as={Link}
              to={'?tab=readme'}
              aria-current={activeTab === 'readme' ? 'page' : undefined}
            >
              README
            </UnderlineNav.Item>
            <UnderlineNav.Item
              icon={LogIcon}
              as={Link}
              to={'?tab=transparency'}
              aria-current={activeTab === 'transparency' ? 'page' : undefined}
            >
              Transparency
            </UnderlineNav.Item>
          </UnderlineNav>
          <div className={styles['marketplace-content-container__content']}>{content}</div>
        </div>
      ) : (
        <div data-testid="markdown-body" className={styles['marketplace-content-container']}>
          {readmeContent}
        </div>
      )}
      {app.copilotApp && <CopilotListingRequirement />}
      <Stack className="d-md-none">
        <Languages supportedLanguages={supportedLanguages} />
        <Resources app={app} />
      </Stack>
      {!marketplaceFreeInstallFlag || !app.copilotApp ? (
        <Plans listing={app} planInfo={planInfo} />
      ) : (
        <TermsOfService planInfo={planInfo} plan={selectedPlan} listing={app} />
      )}
    </Stack>
  )
}
