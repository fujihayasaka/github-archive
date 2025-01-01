import {useCurrentRepository} from '@github-ui/current-repository'
import {pullRequestPath} from '@github-ui/paths'
import {Banner as PrimerBanner} from '@primer/react/experimental'
import {useEffect, useRef} from 'react'

import {WorkbenchBanner} from '../../workbench/components/WorkbenchBanner'
import {useBannerState} from '../../workbench/hooks/use-banner-state'
import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {BannerType} from '../utilities/workspace-editor-types'
import {ComputeLimitBanner} from './ComputeLimitBanner'
import {ConnectionErrorBanner} from './ConnectionErrorBanner'
import {ConnectionReloadBanner} from './ConnectionReloadBanner'
import {CopilotBillingBanner} from './CopilotBillingBanner'
import {IdleSparkBanner} from './IdleSparkBanner'
import {MultipleSparksBanner} from './MultipleSparksBanner'
import {PreviewAuthFailedBanner} from './PreviewAuthFailedBanner'
import {RuntimeLimitBanner} from './RuntimeLimitBanner'
import {SparkInfraLimitBanner} from './SparkInfraLimitBanner'

interface BaseBannerProps {
  title: string
  description: string | React.ReactNode
  primaryAction?: React.ReactNode
  secondaryAction?: React.ReactNode
  onDismiss: () => void
  variant: 'success' | 'warning' | 'critical' | 'info' | 'upsell'
}

function BaseBanner(props: BaseBannerProps) {
  return <PrimerBanner hideTitle className="mx-3 mb-2" {...props} />
}

function CommitSuccessBanner(props: Omit<BaseBannerProps, 'title' | 'description' | 'variant'>) {
  const {pullRequest} = useCurrentPullRequest()
  const repo = useCurrentRepository()

  const pullHref = pullRequestPath({repo, number: Number(pullRequest.number)})

  return (
    <BaseBanner
      variant="success"
      title="Changes committed"
      description={
        <>
          Changes committed to branch <span className="text-bold">{pullRequest.headBranch}</span>.
        </>
      }
      primaryAction={
        <PrimaryAction onClick={() => (window.location.href = pullHref)}>Return to pull request</PrimaryAction>
      }
      {...props}
    />
  )
}

export function Banner() {
  const bannerRef = useRef<HTMLDivElement>(null)
  const dispatch = useWorkspaceEditorUIDispatch()

  const {banner} = useWorkspaceEditorUIState()
  const bannerState = useBannerState()

  useEffect(() => {
    // only works if it's a net new render
    if (bannerRef.current) {
      const timeout = window.setTimeout(() => {
        bannerRef.current?.focus()
      }, 0)

      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [banner, bannerRef])

  const onDismiss = () => {
    dispatch({type: 'SET_BANNER', banner: undefined})
  }

  const props = {
    onDismiss,
  }

  if (!banner && !bannerState) {
    return null
  }

  let bannerToShow: React.ReactNode | null = null
  switch (bannerState || banner) {
    // Banner display order is prioritized as follows (from highest to lowest):
    // spark-infra-limit > copilot-billing > multiple-sparks > idle-spark > runtime-limit > compute-limit
    // This order ensures system-level and billing issues are surfaced before usage-related notices.
    // ⬇️ system states
    case BannerType.SPARK_INFRA_LIMIT:
      bannerToShow = <SparkInfraLimitBanner />
      break
    case BannerType.COPILOT_BILLING:
      bannerToShow = <CopilotBillingBanner />
      break
    case BannerType.COPILOT_CHAT_QUOTA:
      bannerToShow = <WorkbenchBanner />
      break
    // ⬇️ application states
    case BannerType.MULTIPLE_SPARKS:
      bannerToShow = <MultipleSparksBanner />
      break
    case BannerType.COMPUTE_LIMIT:
      bannerToShow = <ComputeLimitBanner />
      break
    case BannerType.IDLE_SPARK:
      bannerToShow = <IdleSparkBanner />
      break
    case BannerType.RUNTIME_LIMIT:
      bannerToShow = <RuntimeLimitBanner />
      break
    // ⬆️ end system and application states
    case BannerType.COMMIT_SUCCESS:
      bannerToShow = <CommitSuccessBanner {...props} />
      break
    case BannerType.CONNECTION_ERROR:
      bannerToShow = <ConnectionErrorBanner />
      break
    case BannerType.CONNECTION_RELOAD:
      bannerToShow = <ConnectionReloadBanner />
      break
    case BannerType.PREVIEW_AUTH_FAILED:
      bannerToShow = <PreviewAuthFailedBanner />
      break
    default:
      break
  }

  return bannerToShow ? (
    <div ref={bannerRef} tabIndex={-1}>
      {bannerToShow}
    </div>
  ) : null
}

export const PrimaryAction = PrimerBanner.PrimaryAction
export const SecondaryAction = PrimerBanner.SecondaryAction
