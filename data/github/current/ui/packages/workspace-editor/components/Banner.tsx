import {useCurrentRepository} from '@github-ui/current-repository'
import {pullRequestPath} from '@github-ui/paths'
import {Banner as PrimerBanner} from '@primer/react/experimental'
import {useEffect, useRef} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'

interface BaseBannerProps {
  title: string
  description: string | React.ReactNode
  primaryAction?: React.ReactNode
  secondaryAction?: React.ReactNode
  onDismiss: () => void
  variant: 'success' | 'warning' | 'critical' | 'info' | 'upsell'
}

function BaseBanner(props: BaseBannerProps) {
  return <PrimerBanner hideTitle className="mt-2" {...props} />
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

  // potentially to support multiple banners, even if just one for now
  const bannerToShow = banner === 'commit-success' ? <CommitSuccessBanner {...props} /> : null

  return bannerToShow ? (
    <div ref={bannerRef} tabIndex={-1}>
      {bannerToShow}
    </div>
  ) : null
}

export const PrimaryAction = PrimerBanner.PrimaryAction
export const SecondaryAction = PrimerBanner.SecondaryAction
