import type {AuthorSettings} from '@github-ui/commit-attribution'
import {CommitAttribution as UiCommitAttribution} from '@github-ui/commit-attribution'
import type {RepositoryNWO} from '@github-ui/current-repository'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {useClientValue} from '@github-ui/use-client-value'
import {RelativeTime} from '@primer/react'
import type {PropsWithChildren} from 'react'

import {useFindDeferredCommitData} from '../contexts/DeferredCommitDataContext'
import type {BaseCommit} from '../shared/types'

interface CommitAttributionProps {
  commit: BaseCommit
  repo: RepositoryNWO
  settings?: Partial<AuthorSettings>
  textVariant?: React.ComponentProps<typeof UiCommitAttribution>['textVariant']
}

export function CommitAttribution({
  commit,
  repo,
  children,
  settings,
  textVariant,
}: PropsWithChildren<CommitAttributionProps>) {
  const deferredData = useFindDeferredCommitData(commit.oid)
  const [isSSR] = useClientValue(() => false, true, [])

  return (
    <UiCommitAttribution
      authors={commit.authors}
      committer={commit.committer}
      committerAttribution={commit.committerAttribution}
      onBehalfOf={deferredData?.onBehalfOf}
      repo={repo}
      includeVerbs
      authorSettings={{fontWeight: 'normal', fontColor: 'fg.muted', avatarSize: 16, ...settings}}
      textVariant={textVariant}
    >
      {!isSSR && <RelativeTime className="pl-1" datetime={commit.committedDate} />}
      {isSSR && <LoadingSkeleton variant="rounded" className="d-none d-sm-flex ml-1" width="60px" />}
      {children}
    </UiCommitAttribution>
  )
}
