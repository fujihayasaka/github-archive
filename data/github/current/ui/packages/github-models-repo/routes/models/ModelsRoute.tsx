import {Link, LinkButton, Timeline, IconButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {ModelsRepoLayout} from '../../components/ModelsRepoLayout'
import {
  AiModelIcon,
  AppsIcon,
  ArrowUpRightIcon,
  GitCommitIcon,
  GitCompareIcon,
  PlusIcon,
  PulseIcon,
  SidebarCollapseIcon,
  WorkflowIcon,
} from '@primer/octicons-react'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {PromptList} from '../../components/PromptList'
import {useCallback, useState, type PropsWithChildren} from 'react'
import type {ModelRepoPayload} from '../../types'
import {MiniGettingStarted} from './components/MiniGettingStarted'
import {GetStartedBox} from './components/GetStartedBox'
import styles from './ModelsRoute.module.css'
import {OnboardingVideoBanner} from './components/OnboardingVideoBanner'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {dismissUserNoticePath, repoModelsPromptPath} from '@github-ui/paths'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {aboutGitHubModelsDocsUrl} from '../../constants'

export function ModelsRoute() {
  const {
    repository,
    canEdit,
    prompts,
    totalPrompts,
    sampleActionsUrl,
    onboardingVideoBannerDismissed,
    compareModelsUrl,
  } = useAppPayload<ModelRepoPayload>()
  const [showDialog, setShowDialog] = useState(false)
  const [fileTreeExpanded, setFileTreeExpanded] = useState(true)
  const showBannerOnLand = useFeatureFlag('github_models_onboarding_video_banner') && !onboardingVideoBannerDismissed
  const [isOnboardingVideoBannerOpen, setIsOnboardingVideoBannerOpen] = useState(showBannerOnLand)

  const promptCount = prompts.length
  const promptListHeaderText =
    totalPrompts > promptCount
      ? `Showing ${promptCount} of ${totalPrompts} prompts`
      : `${promptCount} prompt${promptCount !== 1 ? 's' : ''} found`

  const dismissOnboardingVideoBanner = useCallback(() => {
    if (showBannerOnLand) {
      verifiedFetch(dismissUserNoticePath({noticeName: 'github_models_onboarding_video_banner'}), {method: 'POST'})
    }
    setIsOnboardingVideoBannerOpen(false)
  }, [showBannerOnLand])

  return (
    <ModelsRepoLayout fileTreeExpanded={fileTreeExpanded} setFileTreeExpanded={setFileTreeExpanded}>
      <div className={fileTreeExpanded ? 'pt-2 pr-sm-5' : 'pt-2 px-sm-5'}>
        <div className="d-flex flex-items-center">
          {!fileTreeExpanded && (
            <IconButton
              onClick={() => setFileTreeExpanded(true)}
              aria-label="Expand menu"
              icon={SidebarCollapseIcon}
              variant="invisible"
              // eslint-disable-next-line @github-ui/github-monorepo/no-sx
              sx={{marginRight: '8px'}}
            />
          )}
          <h1 className={styles.title}>Overview</h1>
        </div>
        <p className={styles.titleSubtext}>
          Build your AI products&mdash;right inside GitHub. Create prompts, test models, and ship AI-powered features
          with built-in tools for model access, prompt collaboration, and lightweight evaluation.{' '}
          <Link inline href={aboutGitHubModelsDocsUrl}>
            Read the docs
          </Link>{' '}
          to learn more.
        </p>

        <AccessProtectedBlock canEdit={canEdit}>
          <h2 className={styles.subtitle}>Get started</h2>
          <div className="d-flex mb-3">
            {isOnboardingVideoBannerOpen && <OnboardingVideoBanner onDismiss={dismissOnboardingVideoBanner} />}
          </div>
          <div className="d-flex gap-3 flex-column flex-xl-row">
            <GetStartedBox icon={PulseIcon} href="models/prompt/new?sample" callToAction="Create a sample prompt" />
            <GetStartedBox
              icon={GitCompareIcon}
              href={`${repoModelsPromptPath({
                repo: {
                  name: repository.name,
                  ownerLogin: repository.ownerLogin,
                },
                commitish: repository.defaultBranch,
                action: 'compare',
              })}?sample`}
              callToAction="Compare multiple prompts"
            />
            {/* When there are no available models, compareModelsUrl is undefined */}
            {compareModelsUrl && (
              <GetStartedBox icon={AiModelIcon} href={compareModelsUrl} callToAction="Compare models" />
            )}
          </div>
        </AccessProtectedBlock>

        <div className="d-flex flex-items-center mt-5 mb-2">
          <div className="flex-1">
            <h2 className={styles.subtitle}>Prompts</h2>
            <p className={styles.subtext}>Create, evaluate, and iterate on prompts right inside your repo.</p>
          </div>
          {canEdit && (
            <LinkButton href="models/prompt/new" leadingVisual={PlusIcon} variant="primary">
              New prompt
            </LinkButton>
          )}
        </div>

        <PromptList
          canEdit={canEdit}
          headerText={promptListHeaderText}
          totalPrompts={totalPrompts}
          prompts={prompts}
          repository={repository}
          showViewAll={prompts.length > 0 && prompts.length < totalPrompts}
        />

        {compareModelsUrl && (
          <>
            <MiniGettingStarted showDialog={showDialog} setShowDialog={setShowDialog} />

            <Timeline>
              <Timeline.Item>
                <Timeline.Badge
                  // eslint-disable-next-line @github-ui/github-monorepo/no-sx
                  sx={{
                    background: 'var(--bgColor-success-muted)',
                  }}
                >
                  <AppsIcon />
                </Timeline.Badge>
                <Timeline.Body>
                  <Link className={styles.timelineLink} href="/marketplace/models/catalog">
                    Explore 40+ models in the catalog <ArrowUpRightIcon className="fgColor-muted" />
                  </Link>
                  <p className="mb-0">
                    Compare models in the playground&mdash;test parameters, token usage, and latency to find the right
                    fit for your use case.
                  </p>
                </Timeline.Body>
              </Timeline.Item>
              <Timeline.Item>
                <Timeline.Badge
                  // eslint-disable-next-line @github-ui/github-monorepo/no-sx
                  sx={{
                    background: 'var(--bgColor-success-muted)',
                  }}
                >
                  <GitCommitIcon />
                </Timeline.Badge>
                <Timeline.Body>
                  <Link
                    className={styles.timelineLink}
                    href="https://docs.github.com/en/early-access/models/storing-prompts-in-github-repositories"
                  >
                    Power your prompt with the right model <ArrowUpRightIcon className="fgColor-muted" />
                  </Link>
                  <p className="mb-0">
                    Test and compare models against your prompt to find the best fit, then commit it directly to your
                    project when you&apos;re ready.
                  </p>
                </Timeline.Body>
              </Timeline.Item>
              <Timeline.Item
                // eslint-disable-next-line @github-ui/github-monorepo/no-sx
                sx={{
                  ':before': {
                    background: 'linear-gradient(var(--borderColor-muted) 50%, transparent 51%)',
                  },
                }}
              >
                <Timeline.Badge
                  // eslint-disable-next-line @github-ui/github-monorepo/no-sx
                  sx={{
                    background: 'var(--bgColor-success-muted)',
                  }}
                >
                  <WorkflowIcon />
                </Timeline.Badge>
                <Timeline.Body>
                  <Link className={styles.timelineLink} href={sampleActionsUrl}>
                    Instrument your Actions workflow with models <ArrowUpRightIcon className="fgColor-muted" />
                  </Link>
                  <p className="mb-0">Set up a new GitHub Actions workflow using models.</p>
                </Timeline.Body>
              </Timeline.Item>
            </Timeline>
          </>
        )}
      </div>
    </ModelsRepoLayout>
  )
}

function AccessProtectedBlock({
  canEdit,
  children,
}: PropsWithChildren<{
  canEdit: boolean
}>) {
  if (!canEdit) return <ReadOnlyAccess />

  // Note; I can see us adding all our other permutations of disabled states here, to continually render a consistent banner.

  return <>{children}</>
}

function ReadOnlyAccess() {
  return (
    <Banner
      title="You do not have access to GitHub Models on this repository"
      description={
        <>
          You need write permissions or higher for this repository to use GitHub Models.{' '}
          <Link inline href={aboutGitHubModelsDocsUrl}>
            Learn more about GitHub Models.
          </Link>
        </>
      }
      variant="warning"
    />
  )
}
