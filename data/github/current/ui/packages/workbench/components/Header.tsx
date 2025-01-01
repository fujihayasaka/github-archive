import {useCurrentRepository} from '@github-ui/current-repository'
import {ownerPath, repositoryPath} from '@github-ui/paths'
import {useQuery} from '@github-ui/react-query'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CodeIcon, EyeIcon, MarkGithubIcon, ShareIcon, SparkleFillIcon, ThreeBarsIcon} from '@primer/octicons-react'
import {BranchName, Breadcrumbs, IconButton, Link, LinkButton, SegmentedControl, Stack} from '@primer/react'
import type React from 'react'
import {memo, useCallback} from 'react'

import {ssrSafeLocation} from '../../ssr-utils/ssr-globals'
import {CommandTask} from '../../workspace-editor/utilities/terminal-reducer'
import {useTerminalContext} from '../contexts/TerminalContext'
import {DeployButton} from './Deployment/DeployButton'
import styles from './Header.module.css'

export interface HeaderProps {
  onCommitClick?: () => void
  copilotHeaderButtonRef?: React.RefObject<HTMLButtonElement>
  commitButtonRef?: React.RefObject<HTMLButtonElement>
  forwardedUrl?: string | undefined
  openIterationModal: () => void
}

// Temporarily hide the share button since it doesn't do anything.
// This can be replaced with a feature flag check, or simply removed once we wire up the functionality.
const showShareButton = false

export const GlobalSidePanel = () => {
  const {data, isLoading} = useQuery({
    queryKey: ['side-panels-global'],
    queryFn: async () => {
      const resp = await verifiedFetch('/_side-panels/global')
      return resp.text()
    },
  })

  if (isLoading) {
    return <IconButton aria-label="Open global navigation menu" icon={ThreeBarsIcon} />
  } else {
    return <SafeHTMLBox html={data as SafeHTMLString} />
  }
}

export const Header = memo(function Header(props: HeaderProps) {
  const repo = useCurrentRepository()
  const repoHref = repositoryPath({owner: repo.ownerLogin, repo: repo.name})
  const ownerHref = ownerPath({owner: repo.ownerLogin})

  const terminalContext = useTerminalContext()
  const {
    executeCommand,
    state: {history},
  } = terminalContext

  const handleDeploymentStart = useCallback(async () => {
    const command = `./deploy.sh`
    await executeCommand(command, CommandTask.Build)
  }, [executeCommand])

  const buildCommand = history[CommandTask.Build]
  const {exitCode, channel, output, loading, startTime, endTime} = buildCommand
  const isRunning = !!(startTime && !endTime) || loading

  const hasCommandExecuted = channel != null || exitCode != null || loading
  const deploymentMatches = output.match(/Executing the deployment upload script/)
  const isBuildComplete = !!(deploymentMatches && deploymentMatches.length > 0)

  const urlMatches = output.match(/https:\/\/.*\.github\.app/)

  const deploymentUrl = hasCommandExecuted && urlMatches ? urlMatches[0] : ''
  const origin = ssrSafeLocation.origin

  return (
    <Stack direction="horizontal" align="center" wrap="wrap" gap="condensed" justify="space-between" padding="none">
      <Stack direction="horizontal" align="center" wrap="nowrap">
        <Stack direction="horizontal" align="center">
          <GlobalSidePanel />
          <Link aria-label="Home" className={styles.homepageLink} href="/">
            <MarkGithubIcon size={32} className={styles.logo} />
          </Link>
          <LinkButton variant="invisible" href={`${origin}/spark/apps`}>
            <div className={styles.productName}>Spark</div>
          </LinkButton>
        </Stack>

        <Stack direction="horizontal" align="center" wrap="nowrap" className="hide-sm flex-1">
          <Breadcrumbs className={styles.breadcrumbs}>
            <Breadcrumbs.Item className={styles.breadcrumbLink} href={ownerHref}>
              {repo.ownerLogin}
            </Breadcrumbs.Item>
            <Breadcrumbs.Item className={styles.breadcrumbLink} href={repoHref}>
              {repo.name}
            </Breadcrumbs.Item>
          </Breadcrumbs>
          <BranchName>main</BranchName>
        </Stack>
      </Stack>

      <SegmentedControl aria-label="Mode">
        <SegmentedControl.Button leadingIcon={CodeIcon} defaultSelected>
          Code
        </SegmentedControl.Button>
        <SegmentedControl.Button leadingIcon={EyeIcon}>Preview</SegmentedControl.Button>
      </SegmentedControl>

      {/* Buttons wrap to second line on narrow viewports */}
      <Stack direction="horizontal" align="center">
        <IconButton aria-label="Iterate on this spark" icon={SparkleFillIcon} onClick={props.openIterationModal} />
        {showShareButton && <IconButton aria-label="Share this spark" icon={ShareIcon} />}
        <DeployButton
          repo={repo}
          description="A fun family-friendly Wordle-style game"
          buildStatus={!isRunning && !isBuildComplete ? 'failure' : isBuildComplete ? 'success' : 'pending'}
          deployStatus={isRunning ? 'pending' : deploymentUrl.length > 0 ? 'success' : 'failure'}
          deployUrl={deploymentUrl}
          isDeploying={isRunning}
          onDeploymentStart={handleDeploymentStart}
        />
      </Stack>
    </Stack>
  )
})
