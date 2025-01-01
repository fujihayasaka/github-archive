import {PageHeader, Stack} from '@primer/react'
import {getPRStatusIcon} from './PRStatusIcon'
import {usePullContext} from '../contexts/PullContext'
import {useCurrentRepository} from '@github-ui/current-repository'

export function SessionsHeader() {
  const {
    pull: {title: pullTitle, number: pullNumber, state: pullState, reviewable_state: pullReviewableState},
  } = usePullContext()
  const {ownerLogin, name: repoName} = useCurrentRepository()

  return (
    <PageHeader aria-label="Session PR Header">
      <PageHeader.ContextArea hidden={false}>
        <PageHeader.ParentLink
          aria-label="Back to Pull Request link"
          hidden={false}
          href={`/${ownerLogin}/${repoName}/pull/${pullNumber}`}
        >
          Back to pull request
        </PageHeader.ParentLink>
      </PageHeader.ContextArea>
      <PageHeader.TitleArea>
        <PageHeader.LeadingVisual>
          {getPRStatusIcon(pullReviewableState === 'draft' ? 'draft' : pullState)}
        </PageHeader.LeadingVisual>
        <Stack direction="horizontal">
          <PageHeader.Title as="h3">
            {pullTitle}
            <span className="f3 text-light color-fg-muted">
              {' #'}
              {pullNumber}
            </span>
          </PageHeader.Title>
        </Stack>
      </PageHeader.TitleArea>
    </PageHeader>
  )
}
