import {useCallback, useState, useMemo, useEffect} from 'react'
import {RepositoryAndIssuePicker, type PickerType} from '@github-ui/item-picker/RepositoryAndIssuePicker'
import type {IssuePickerItem} from '@github-ui/item-picker/IssuePicker'
import {graphql, useRelayEnvironment} from 'react-relay'
import {addBlockedByMutation} from '../../../mutations/add-blocked-by-mutation'
import {removeBlockedByMutation} from '../../../mutations/remove-blocked-by-mutation'

import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import styles from './DependenciesPicker.module.css'
import {useAnalytics} from '@github-ui/use-analytics'
import {noop} from '@github-ui/noop'

import type {
  DependenciesPickerBlockingBlockedByIssuesQuery,
  DependenciesPickerBlockingBlockedByIssuesQuery$data,
} from './__generated__/DependenciesPickerBlockingBlockedByIssuesQuery.graphql'

export type DependenciesPickerProps = {
  type: 'blockedBy' | 'blocking'
  onClose?: () => void
  issueId: string
  organization: string
  defaultRepositoryNameWithOwner: string
  anchorRef: React.RefObject<HTMLElement>
  onError?: (errors: Error[]) => void
}

export const DependenciesPickerBlockingBlockedByIssuesGraphqlQuery = graphql`
  query DependenciesPickerBlockingBlockedByIssuesQuery($id: ID!) {
    node(id: $id) {
      ... on Issue {
        id
        blockedBy(first: 100) {
          nodes {
            id
          }
        }
        blocking(first: 100) {
          nodes {
            id
          }
        }
      }
    }
  }
`

export function DependenciesPicker({
  type,
  onClose,
  issueId,
  organization,
  defaultRepositoryNameWithOwner,
  anchorRef,
  onError = noop,
}: DependenciesPickerProps) {
  const environment = useRelayEnvironment()
  const [state, setState] = useState<'loading' | 'error' | 'success' | 'idle'>('idle')
  const [queryData, setQueryData] = useState<DependenciesPickerBlockingBlockedByIssuesQuery$data | null>(null)
  const {sendAnalyticsEvent} = useAnalytics()

  const fetchBlockingBlockedByData = useCallback(async () => {
    setState('loading')
    clientSideRelayFetchQueryRetained<DependenciesPickerBlockingBlockedByIssuesQuery>({
      environment,
      query: DependenciesPickerBlockingBlockedByIssuesGraphqlQuery,
      variables: {id: issueId},
    }).subscribe({
      next: data => {
        setQueryData(data)
        setState('success')
      },
      error: () => {
        setState('error')
      },
    })
  }, [environment, issueId])

  useEffect(() => {
    if (state !== 'idle') return
    if (type === 'blockedBy' || type === 'blocking') {
      fetchBlockingBlockedByData()
    }
  }, [environment, fetchBlockingBlockedByData, issueId, state, type])

  const [pickerType, setPickerType] = useState<PickerType>('Issue')

  const blockedByIssueIds = useMemo(() => {
    if (!queryData?.node?.blockedBy?.nodes) return []
    return queryData.node.blockedBy.nodes.filter(issue => !!issue).map(issue => issue.id)
  }, [queryData?.node?.blockedBy?.nodes])

  const blockingIssueIds = useMemo(() => {
    if (!queryData?.node?.blocking?.nodes) return []
    return queryData.node.blocking.nodes.filter(issue => !!issue).map(issue => issue.id)
  }, [queryData?.node?.blocking?.nodes])

  const onPickerTypeChange = useCallback(
    (t: PickerType) => {
      setPickerType(t)
      if (t === null && onClose) {
        onClose()
        setState('idle')
      }
    },
    [onClose],
  )

  const onIssueSelection = useCallback(
    async (selectedIssues: IssuePickerItem[]) => {
      if (type === 'blockedBy') {
        // Compute the set difference between the currently selected issue IDs and the newly selected issue IDs
        const selectedIssueIds = new Set(selectedIssues.map(issue => issue.id))
        const blockedByIssueIdsSet = new Set(blockedByIssueIds)
        const issuesToAdd = Array.from(selectedIssueIds).filter(id => !blockedByIssueIdsSet.has(id))
        const issuesToRemove = Array.from(blockedByIssueIdsSet).filter(id => !selectedIssueIds.has(id))

        sendAnalyticsEvent(`issue_viewer.dependencies_picker.blocked_by`, 'ISSUE_DEPENDENCIES_PICKER', {
          issuesToAdd: issuesToAdd.length,
          issuesToRemove: issuesToRemove.length,
        })

        const mutationErrorPromises: Array<Promise<Error | null>> = []

        for (const blockingIssueId of issuesToAdd) {
          mutationErrorPromises.push(
            new Promise(resolve => {
              // Call the mutation to add the blockedBy relationship
              addBlockedByMutation({
                environment,
                input: {
                  issueId,
                  blockingIssueId,
                },
                onCompleted: () => resolve(null),
                onError: error => {
                  resolve(error)
                },
              })
            }),
          )
        }

        for (const blockingIssueId of issuesToRemove) {
          mutationErrorPromises.push(
            new Promise(resolve => {
              // Call the mutation to remove the blockedBy relationship
              removeBlockedByMutation({
                environment,
                input: {
                  issueId,
                  blockingIssueId,
                },
                onCompleted: () => resolve(null),
                onError: error => {
                  resolve(error)
                },
              })
            }),
          )
        }
        const errors = (await Promise.all(mutationErrorPromises)).flatMap(error => error ?? [])
        onError(errors)
      } else if (type === 'blocking') {
        // Compute the set difference between the currently selected issue IDs and the newly selected issue IDs
        const selectedIssueIds = new Set(selectedIssues.map(issue => issue.id))
        const blockingIssueIdsSet = new Set(blockingIssueIds)
        const issuesToAdd = Array.from(selectedIssueIds).filter(id => !blockingIssueIdsSet.has(id))
        const issuesToRemove = Array.from(blockingIssueIdsSet).filter(id => !selectedIssueIds.has(id))

        sendAnalyticsEvent(`issue_viewer.dependencies_picker.blocking`, 'ISSUE_DEPENDENCIES_PICKER', {
          issuesToAdd: issuesToAdd.length,
          issuesToRemove: issuesToRemove.length,
        })

        const mutationErrorPromises: Array<Promise<Error | null>> = []
        for (const blockedIssueId of issuesToAdd) {
          mutationErrorPromises.push(
            new Promise(resolve => {
              // Call the mutation to add the blocking relationship
              addBlockedByMutation({
                environment,
                input: {
                  issueId: blockedIssueId,
                  blockingIssueId: issueId,
                },
                onCompleted: () => resolve(null),
                onError: error => {
                  resolve(error)
                },
              })
            }),
          )
        }

        for (const blockedIssueId of issuesToRemove) {
          mutationErrorPromises.push(
            new Promise(resolve => {
              // Call the mutation to remove the blocking relationship
              removeBlockedByMutation({
                environment,
                input: {
                  issueId: blockedIssueId,
                  blockingIssueId: issueId,
                },
                onCompleted: () => resolve(null),
                onError: error => {
                  resolve(error)
                },
              })
            }),
          )
        }
        const errors = (await Promise.all(mutationErrorPromises)).flatMap(error => error ?? [])
        onError(errors)
      }
    },
    [type, blockedByIssueIds, sendAnalyticsEvent, onError, environment, issueId, blockingIssueIds],
  )

  const hiddenIssueIds = useMemo(() => {
    const ids = [issueId]
    if (type === 'blockedBy') {
      ids.push(...blockingIssueIds)
    } else if (type === 'blocking') {
      ids.push(...blockedByIssueIds)
    }
    return ids
  }, [type, issueId, blockingIssueIds, blockedByIssueIds])

  return (
    <RepositoryAndIssuePicker
      anchorElement={props => {
        const {ref} = props as {
          ref: React.MutableRefObject<HTMLElement | null>
        }
        if (ref) {
          ref.current = anchorRef.current
        }
        return <></>
      }}
      onIssueSelection={onIssueSelection}
      organization={organization}
      defaultRepositoryNameWithOwner={defaultRepositoryNameWithOwner}
      pickerType={pickerType}
      onPickerTypeChange={onPickerTypeChange}
      selectedIssueIds={type === 'blockedBy' ? blockedByIssueIds : blockingIssueIds}
      hiddenIssueIds={hiddenIssueIds}
      issuePickerProps={{
        selectionVariant: 'multiple',
        isLoading: state === 'loading',
        subtitle: type === 'blockedBy' ? 'Mark current issue as blocked by…' : 'Mark current issue as blocking…',
        className: styles.DependenciesPicker,
        notice:
          state === 'error'
            ? {
                variant: 'error',
                text: `We couldn't load the issues. Try reloading the page, or if the problem persists, contact support.`,
              }
            : undefined,
      }}
    />
  )
}
