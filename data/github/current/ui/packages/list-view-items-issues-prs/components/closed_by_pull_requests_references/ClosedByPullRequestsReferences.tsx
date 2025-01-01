import {GitPullRequestIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, Spinner, Text, type BetterSystemStyleObject} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'
import {graphql, useFragment, useLazyLoadQuery} from 'react-relay'

import type {ClosedByPullRequestsReferences$key} from './__generated__/ClosedByPullRequestsReferences.graphql'
import {PullRequest} from './PullRequest'
import {Suspense, useCallback, useRef, useState} from 'react'

import type {ClosedByPullRequestsReferencesQuery} from './__generated__/ClosedByPullRequestsReferencesQuery.graphql'

import type {ClosedByPullRequestsReferencesList$key} from './__generated__/ClosedByPullRequestsReferencesList.graphql'

type Props = {
  issueId: string
  closedByPullRequestsReferencesKey: ClosedByPullRequestsReferences$key
}

export function ClosedByPullRequestsReferences({issueId, closedByPullRequestsReferencesKey}: Props) {
  const data = useFragment(
    graphql`
      fragment ClosedByPullRequestsReferences on Issue @argumentDefinitions(first: {type: "Int", defaultValue: 0}) {
        closedByPullRequestsReferences(first: $first, includeClosedPrs: true) {
          totalCount
        }
      }
    `,
    closedByPullRequestsReferencesKey,
  )
  const totalCount = data?.closedByPullRequestsReferences?.totalCount ?? 0

  const [wasTriggered, setWasTriggered] = useState(false)
  const anchorRef = useRef(null)
  const clickHandler = useCallback(() => setWasTriggered(!wasTriggered), [wasTriggered])

  if (totalCount === 0) return null

  if (!wasTriggered) {
    return <AnchorElement onClick={clickHandler} totalCount={totalCount} anchorRef={anchorRef} />
  }

  return totalCount === 1 ? (
    <Suspense fallback={<AnchorElement totalCount={totalCount} anchorRef={anchorRef} />}>
      <ClosedByPullRequestsReferencesInternal
        issueId={issueId}
        totalCount={totalCount}
        open={wasTriggered}
        setOpen={clickHandler}
        anchorRef={anchorRef}
      />
    </Suspense>
  ) : (
    <>
      <AnchorElement totalCount={totalCount} anchorRef={anchorRef} />
      <ActionMenu open={wasTriggered} onOpenChange={setWasTriggered} anchorRef={anchorRef}>
        <ActionMenu.Overlay>
          <ActionList sx={{width: '300px'}}>
            <Suspense fallback={<CenteredLoadingSpinner />}>
              <ClosedByPullRequestsReferencesInternal
                issueId={issueId}
                totalCount={totalCount}
                open={wasTriggered}
                setOpen={clickHandler}
                anchorRef={anchorRef}
              />
            </Suspense>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
}

function ClosedByPullRequestsReferencesInternal({
  issueId,
  ...props
}: {
  issueId: string
  totalCount: number
  open: boolean
  setOpen: (open: boolean) => void
  anchorRef: React.MutableRefObject<HTMLDivElement | null>
}) {
  const data = useLazyLoadQuery<ClosedByPullRequestsReferencesQuery>(
    graphql`
      query ClosedByPullRequestsReferencesQuery($id: ID!) {
        node(id: $id) {
          ... on Issue {
            ...ClosedByPullRequestsReferencesList
          }
        }
      }
    `,
    {
      id: issueId,
    },
  )

  if (!data.node) return <>{'no data'}</>

  return <ClosedByPullRequestsReferencesList closedByPullRequestsReferencesKey={data.node} {...props} />
}

function ClosedByPullRequestsReferencesList({
  closedByPullRequestsReferencesKey,
  totalCount,
}: {
  closedByPullRequestsReferencesKey: ClosedByPullRequestsReferencesList$key
  totalCount: number
  open: boolean
  setOpen: (open: boolean) => void
  anchorRef: React.MutableRefObject<HTMLDivElement | null>
}) {
  const data = useFragment(
    graphql`
      fragment ClosedByPullRequestsReferencesList on Issue
      @argumentDefinitions(first: {type: "Int", defaultValue: 10}) {
        closedByPullRequestsReferences(first: $first, includeClosedPrs: true)
          @connection(key: "ClosedByPullRequestsReferences__closedByPullRequestsReferences") {
          edges {
            node {
              ...PullRequest
            }
          }
        }
      }
    `,
    closedByPullRequestsReferencesKey,
  )

  const pullRequests = (data.closedByPullRequestsReferences?.edges || []).flatMap(a => (a && a.node ? a.node : []))

  return (
    <>
      {totalCount === 1 && <PullRequest key={`pr${0}`} pullRequest={pullRequests[0]!} hovercard />}
      {totalCount > 1 && (
        <>
          {pullRequests.map((pr, index) => (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <PullRequest key={`pr${index}`} pullRequest={pr} />
          ))}
        </>
      )}
    </>
  )
}

type AnchorProps = {
  totalCount: number
  anchorRef: React.MutableRefObject<HTMLDivElement | null>
  onClick?: () => void
}

const Element = ({anchorRef, onClick, totalCount}: AnchorProps) => (
  <Box
    ref={anchorRef}
    tabIndex={0}
    sx={{display: 'flex', alignItems: 'center', cursor: 'pointer'}}
    onClick={onClick}
    onMouseEnter={() => {
      if (totalCount === 1) {
        onClick?.()
      }
    }}
    onFocus={() => {
      if (totalCount === 1) {
        onClick?.()
      }
    }}
  >
    <GitPullRequestIcon size={16} />
    <Text sx={{ml: 1}}>{totalCount.toString()}</Text>
  </Box>
)

const AnchorElement = ({totalCount, onClick, anchorRef}: AnchorProps): JSX.Element => {
  return totalCount > 1 ? (
    <Tooltip direction="w" text={`${totalCount} linked PRs`}>
      <Element totalCount={totalCount} onClick={onClick} anchorRef={anchorRef} />
    </Tooltip>
  ) : (
    <Element totalCount={totalCount} onClick={onClick} anchorRef={anchorRef} />
  )
}

function CenteredLoadingSpinner({sx}: {sx?: BetterSystemStyleObject}): JSX.Element {
  return (
    <Box
      data-testid={'loading-pulls'}
      sx={{
        alignItems: 'center',
        display: 'flex',
        flexDirection: 'row',
        justifyContent: 'center',
        width: '100%',
        ...sx,
      }}
    >
      <Spinner />
    </Box>
  )
}
