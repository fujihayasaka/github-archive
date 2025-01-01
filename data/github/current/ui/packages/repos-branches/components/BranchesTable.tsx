import {type FC, type ReactNode, lazy, Suspense, useCallback, useState} from 'react'
import {Box, Label, Text, type BetterSystemStyleObject} from '@primer/react'
import {Blankslate, DataTable, SkeletonBox} from '@primer/react/experimental'

import {GitBranchIcon} from '@primer/octicons-react'
import {useCurrentRepository} from '@github-ui/current-repository'
import type {Branch, BranchMetadata} from '../types'
import BranchDescription from './BranchDescription'
import {AheadBehindCountWidth} from './AheadBehindCount'
import {UpdatedBy} from './UpdatedBy'
import {BranchActionMenu} from './BranchActionMenu'
import {useCurrentUser} from '../contexts/CurrentUserContext'

const StatusCheckRollup = lazy(() => import('./StatusCheckRollup'))
const PullRequestLabel = lazy(() => import('./PullRequestLabel'))
const MergeQueueLabel = lazy(() => import('./MergeQueueLabel'))
const AheadBehindCount = lazy(() => import('./AheadBehindCount'))

export default function BranchesTable({
  labelId,
  branches,
  deferredMetadata,
  showMergeQueueHeader,
  isLarge = false,
}: {
  labelId?: string
  branches: Branch[]
  deferredMetadata?: Map<string, BranchMetadata>
  showMergeQueueHeader?: boolean
  isLarge?: boolean
}) {
  const repo = useCurrentRepository()
  const currentUser = useCurrentUser()
  const [_, setDeletedBranches] = useState<string[]>([])

  const onDelete = useCallback(
    (branchName: string) => {
      const branch = branches.find(b => b.name === branchName)
      if (branch) {
        branch.deleted = true
        branch.deletedAt = new Date().toISOString()
      }
      setDeletedBranches(currentBranches => {
        if (!currentBranches.includes(branchName)) {
          return [...currentBranches, branchName]
        }
        return currentBranches
      })
    },
    [setDeletedBranches, branches],
  )

  const onRestore = useCallback(
    (branchName: string) => {
      const branch = branches.find(b => b.name === branchName)
      if (branch) {
        branch.deleted = false
        branch.deletedAt = undefined
      }
      setDeletedBranches(currentBranches => currentBranches.filter(b => b !== branchName))
    },
    [setDeletedBranches, branches],
  )

  if (branches.length === 0) {
    return (
      <Blankslate border>
        <Blankslate.Visual>
          <GitBranchIcon size="medium" />
        </Blankslate.Visual>
        <Blankslate.Heading>No branches</Blankslate.Heading>
        <Blankslate.Description>No branches match the search</Blankslate.Description>
      </Blankslate>
    )
  }

  return (
    <DataTable
      aria-labelledby={labelId}
      data={branches.map(branch => {
        const metadata = deferredMetadata?.get(branch.name)
        const deletedAt = branch.deletedAt
        const deleted = !!deletedAt

        return {
          id: branch.name,
          ...branch,
          author: branch.author ?? metadata?.author,
          oid: metadata?.oid,
          deletedAt,
          aheadBehind: metadata?.aheadBehind,
          statusCheckRollup: metadata?.statusCheckRollup,
          pullRequest: metadata?.pullRequest,
          mergeQueue: metadata?.mergeQueue,
          maxDiverged: metadata?.maxDiverged,
          isLarge,
          deleted,
        }
      })}
      columns={[
        {
          header: 'Branch',
          field: 'name',
          width: 'grow',
          renderCell: row => <BranchDescription {...row} />,
        },
        {
          header: 'Updated',
          field: 'author',
          width: 180,
          renderCell: ({author, authoredDate, deleted, deletedAt}) => {
            return (
              <VerticallyCenteredCell>
                <>
                  {!deferredMetadata && !deleted && !author ? (
                    // eslint-disable-next-line primer-react/no-system-props
                    <SkeletonBox width="16px" height="16px" className="mr-2" />
                  ) : null}
                  <UpdatedBy user={deleted ? currentUser : author} updatedAt={authoredDate} deletedAt={deletedAt} />
                </>
              </VerticallyCenteredCell>
            )
          },
        },
        {
          header: 'Check status',
          id: 'statusCheckRollup',
          width: 125,
          renderCell: ({oid, statusCheckRollup}) => {
            // eslint-disable-next-line primer-react/no-system-props
            const skeleton = <SkeletonBox width="33%" height="20px" style={{maxWidth: '42px'}} />

            if (!deferredMetadata) {
              return <VerticallyCenteredCell>{skeleton}</VerticallyCenteredCell>
            }

            return oid && statusCheckRollup ? (
              <VerticallyCenteredCell>
                <Suspense fallback={skeleton}>
                  <StatusCheckRollup oid={oid} statusCheckRollup={statusCheckRollup} />
                </Suspense>
              </VerticallyCenteredCell>
            ) : null
          },
        },
        {
          header: () => (
            <Box sx={{display: 'flex', justifyContent: 'center', mr: '3px', flexGrow: 1}}>
              <Text
                sx={{
                  borderRight: '1px solid',
                  borderColor: 'border.default',
                  pr: 1,
                }}
              >
                Behind
              </Text>
              <Text
                sx={{
                  pl: 1,
                }}
              >
                Ahead
              </Text>
            </Box>
          ),
          field: 'aheadBehind',
          width: AheadBehindCountWidth,
          renderCell: ({isDefault, aheadBehind, maxDiverged}) => {
            // eslint-disable-next-line primer-react/no-system-props
            const skeleton = <SkeletonBox width={`${AheadBehindCountWidth - 24}px`} height="20px" />

            if (!deferredMetadata) {
              return <VerticallyCenteredCell>{skeleton}</VerticallyCenteredCell>
            }

            if (isDefault) {
              return (
                <VerticallyCenteredCell sx={{justifyContent: 'center', flexGrow: 1}}>
                  <Label>Default</Label>
                </VerticallyCenteredCell>
              )
            }

            if (aheadBehind) {
              return (
                <Suspense fallback={skeleton}>
                  <AheadBehindCount
                    width={AheadBehindCountWidth - 24}
                    aheadCount={aheadBehind[0]}
                    behindCount={aheadBehind[1]}
                    maxDiverged={maxDiverged}
                  />
                </Suspense>
              )
            }
            return null
          },
        },
        {
          header: showMergeQueueHeader ? 'Merge queue' : 'Pull request',
          id: 'pullRequestOrMergeQueue',
          width: 125,
          renderCell: ({mergeQueue, pullRequest}) => {
            // eslint-disable-next-line primer-react/no-system-props
            const skeleton = <SkeletonBox width="33%" height="20px" style={{maxWidth: '75px'}} />

            if (!deferredMetadata) {
              return <VerticallyCenteredCell>{skeleton}</VerticallyCenteredCell>
            }

            if (mergeQueue) {
              return (
                <VerticallyCenteredCell>
                  <Suspense fallback={skeleton}>
                    <MergeQueueLabel mergeQueueUrl={mergeQueue.path} queueCount={mergeQueue.count} />
                  </Suspense>
                </VerticallyCenteredCell>
              )
            }

            if (pullRequest) {
              return (
                <VerticallyCenteredCell>
                  <Suspense fallback={skeleton}>
                    <PullRequestLabel repo={repo} pullRequest={pullRequest} />
                  </Suspense>
                </VerticallyCenteredCell>
              )
            }

            return null
          },
        },
        {
          header: () => (
            <Text className="sr-only" sx={{position: 'relative'}}>
              Action menu
            </Text>
          ),
          id: 'actionMenu',
          width: 70,
          renderCell: ({
            isDefault,
            name,
            rulesetsPath,
            path,
            deleteable,
            deleteProtected,
            renameable,
            isBeingRenamed,
            oid,
            pullRequest,
            deletedAt,
          }) => (
            <BranchActionMenu
              repo={repo}
              branch={{
                isDefault,
                name,
                rulesetsPath,
                path,
                deleteable,
                deleteProtected,
                renameable,
                isBeingRenamed,
              }}
              oid={oid}
              pullRequest={pullRequest}
              onDelete={onDelete}
              onRestore={onRestore}
              sx={{float: 'right'}}
              deletedAt={deletedAt}
            />
          ),
        },
      ]}
    />
  )
}

const VerticallyCenteredCell: FC<{sx?: BetterSystemStyleObject; children: ReactNode}> = ({sx, children}) => (
  <Box sx={{display: 'flex', alignItems: 'center', height: 32, ...sx}}>{children}</Box>
)
