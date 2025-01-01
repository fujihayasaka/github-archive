import {useCurrentRepository} from '@github-ui/current-repository'
import {ownerPath, pullRequestPath, repositoryPath} from '@github-ui/paths'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useQuery} from '@github-ui/react-query'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import {verifiedFetch} from '@github-ui/verified-fetch'
import type {WebCommitDialogState} from '@github-ui/web-commit-dialog'
import {MarkGithubIcon, ThreeBarsIcon} from '@primer/octicons-react'
import {Breadcrumbs, Button, IconButton, Link, Stack} from '@primer/react'
import type {ReviewAppPayload} from '../../prompt/types'
import styles from './ReviewPromptHeader.module.css'

export interface HeaderProps {
  canCommit: boolean
  setDialogState: (state: WebCommitDialogState) => void
}

const GlobalSidePanel = () => {
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

export function ReviewPromptHeader({canCommit, setDialogState}: HeaderProps) {
  const {
    payload: {pull},
  } = useAppPayload<ReviewAppPayload>()

  const repo = useCurrentRepository()
  const pullHref = pullRequestPath({repo, number: Number(pull.number)})
  const repoHref = repositoryPath({owner: repo.ownerLogin, repo: repo.name})
  const ownerHref = ownerPath({owner: repo.ownerLogin})

  return (
    <Stack
      direction="horizontal"
      align="center"
      wrap="wrap"
      gap="condensed"
      justify="space-between"
      padding="none"
      className="mb-2"
    >
      <Stack direction="horizontal" align="center" wrap="nowrap">
        <Stack direction="horizontal" align="center">
          <GlobalSidePanel />
          <Link aria-label="Homepage" className={styles.homepageLink} href="/">
            <MarkGithubIcon size={32} className={styles.logo} />
          </Link>
        </Stack>

        <Stack direction="horizontal" align="center" wrap="nowrap" className="hide-sm flex-1">
          <Breadcrumbs className={styles.breadcrumbs}>
            <Breadcrumbs.Item className={styles.breadcrumbLink} href={ownerHref}>
              {repo.ownerLogin}
            </Breadcrumbs.Item>
            <Breadcrumbs.Item className={styles.breadcrumbLink} href={repoHref}>
              {repo.name}
            </Breadcrumbs.Item>
            <Breadcrumbs.Item className={styles.breadcrumbLink} href={pullHref}>
              <b>{pull.title}</b>&nbsp;#{pull.number}
            </Breadcrumbs.Item>
          </Breadcrumbs>
          {/* <FeedbackLink /> */}
        </Stack>
      </Stack>

      {/* Buttons wrap to second line on narrow viewports */}
      <Stack direction="horizontal" align="center">
        <Stack direction="horizontal" align="center" wrap="nowrap">
          <Button variant="default" onClick={() => setDialogState('pending')} disabled={!canCommit}>
            Commit changes
          </Button>
        </Stack>
      </Stack>
    </Stack>
  )
}
