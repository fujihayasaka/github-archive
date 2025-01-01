import {Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useCallback, useState} from 'react'
import {dismissRepositoryNoticePathPath, modelsSettingsPath} from '@github-ui/paths'
import {useUser} from '@github-ui/use-user'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useNavigate} from '@github-ui/use-navigate'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {Repository} from '@github-ui/current-repository'

type PaidUsageBannerProps = {
  dismissed: boolean | undefined
  repository: Repository
  businessSlug?: string
  className?: string
}

export function PaidUsageBanner({dismissed = true, repository, businessSlug, className}: PaidUsageBannerProps) {
  const {currentUser} = useUser()
  const [bannerDismissed, setBannerDismissed] = useState(dismissed)
  const billingUiEnabled = useFeatureFlag('github_models_billing_ui')
  const navigate = useNavigate()

  const handleDismiss = useCallback(() => {
    if (!currentUser || !repository?.id) return
    const fetch = async () => {
      const dismissPath = `${dismissRepositoryNoticePathPath(
        currentUser,
      )}?notice_name=github_models_paid_usage_banner_repo&repository_id=${repository.id}`
      const response = await verifiedFetch(dismissPath, {
        method: 'DELETE',
      })
      if (response.ok) {
        setBannerDismissed(true)
      }
    }

    fetch()
  }, [currentUser, repository?.id])

  const navigateToModelSettings = () => {
    if (!repository) return
    const settingsPath = modelsSettingsPath(repository.isOrgOwned, repository.ownerLogin, businessSlug)
    navigate(settingsPath)
  }

  if (!billingUiEnabled || !currentUser || bannerDismissed) {
    return null
  }

  return (
    <Banner
      title="Enable paid models usage"
      hideTitle
      variant="upsell"
      description={
        <>
          {businessSlug
            ? 'Your enterprise has'
            : repository.isOrgOwned
              ? 'Your organization has'
              : 'You currently have'}
          <Link
            href="https://docs.github.com/github-models/use-github-models/prototyping-with-ai-models#rate-limits"
            inline
          >
            free rate limits
          </Link>
          . Enable Models paid usage to avoid interruptions.
        </>
      }
      primaryAction={<Banner.PrimaryAction onClick={navigateToModelSettings}>Enable paid usage</Banner.PrimaryAction>}
      onDismiss={handleDismiss}
      className={className}
    />
  )
}
