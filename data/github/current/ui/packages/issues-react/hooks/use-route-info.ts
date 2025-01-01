import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {useParams} from 'react-router-dom'
import {SEARCH_PARAMS} from '../constants/search-params'
import {addUrlToHistoryStack} from '@github-ui/history'

type UrlParams = {
  owner: string
  repo: string
  number: string
  viewId: string
  type: string
}

export const useRouteInfo = () => {
  const {owner, repo, number, viewId} = useParams<UrlParams>()
  const [internalSidePanelIdentifier, setInternalSidePanelIdentifier] = useState<ItemIdentifier | null>(null)

  const setSidePanelItemIdentifier = useCallback((identifier: ItemIdentifier | null) => {
    const url = new URL(window.location.href, window.location.origin)
    if (identifier) {
      url.searchParams.set(SEARCH_PARAMS.issue, `${identifier.owner}|${identifier.repo}|${identifier.number}`)
    } else {
      url.searchParams.delete(SEARCH_PARAMS.issue)
    }

    setInternalSidePanelIdentifier(identifier)
    addUrlToHistoryStack(url.toString())
  }, [])

  // Ensure that on page load, we have the correct search params
  useEffect(() => {
    const url = new URL(window.location.href, window.location.origin)
    const nwoReference = url.searchParams.get(SEARCH_PARAMS.issue)

    if (!nwoReference) return

    const [itemOwner, itemRepo, itemNumber] = nwoReference.split('|')
    if (!(itemOwner && itemRepo && itemNumber)) return

    const issueNumber = isNaN(parseInt(itemNumber)) ? undefined : parseInt(itemNumber)

    if (!issueNumber) return

    const identifier = {
      number: issueNumber,
      owner: itemOwner,
      repo: itemRepo,
      type: 'Issue',
    } as const

    setInternalSidePanelIdentifier(identifier)
  }, [])

  const sidePanelItemURL = internalSidePanelIdentifier
    ? `/${internalSidePanelIdentifier.owner}/${internalSidePanelIdentifier.repo}/issues/${internalSidePanelIdentifier.number}`
    : ''

  const itemIdentifier = useMemo(() => {
    let parsedNumber = number ? parseInt(number, 10) : undefined
    if (parsedNumber && parsedNumber < 1) {
      parsedNumber = undefined
    }
    return owner && repo && parsedNumber ? ({owner, repo, number: parsedNumber} as ItemIdentifier) : undefined
  }, [number, owner, repo])

  const onCloseSidePanel = useCallback(() => {
    setSidePanelItemIdentifier(null)
  }, [setSidePanelItemIdentifier])

  const onParentIssueActivate = useCallback(
    (e: React.MouseEvent | React.KeyboardEvent, parentIdentifier: ItemIdentifier): boolean => {
      if (!itemIdentifier) return false

      // Only close the side panel if the parent is the same as the current issue
      if (
        parentIdentifier.owner !== itemIdentifier.owner ||
        parentIdentifier.repo !== itemIdentifier.repo ||
        parentIdentifier.number !== itemIdentifier.number
      ) {
        return false
      }

      e.preventDefault()
      onCloseSidePanel()
      return true
    },
    [itemIdentifier, onCloseSidePanel],
  )

  useEffect(() => {
    function onPopState() {
      const url = new URL(window.location.href, window.location.origin)
      const nwoReference = url.searchParams.get(SEARCH_PARAMS.issue)

      if (!nwoReference) {
        setInternalSidePanelIdentifier(null)
        return
      }

      const [itemOwner, itemRepo, itemNumber] = nwoReference.split('|')
      if (!(itemOwner && itemRepo && itemNumber)) return

      const issueNumber = isNaN(parseInt(itemNumber)) ? undefined : parseInt(itemNumber)
      if (!issueNumber) return

      // We don't want to open the side panel for the issue that is currently being viewed
      if (
        itemOwner === itemIdentifier?.owner &&
        itemRepo === itemIdentifier?.repo &&
        issueNumber === itemIdentifier?.number
      ) {
        return
      }

      const identifier = {
        number: issueNumber,
        owner: itemOwner,
        repo: itemRepo,
        type: 'Issue',
      } as const

      setInternalSidePanelIdentifier(identifier)
    }

    window.addEventListener('popstate', onPopState)

    return () => window.removeEventListener('popstate', onPopState)
  }, [itemIdentifier])

  return {
    itemIdentifier,
    viewId,
    sidePanelItemIdentifier: internalSidePanelIdentifier,
    setSidePanelItemIdentifier,
    sidePanelItemURL,
    onCloseSidePanel,
    onParentIssueActivate,
  }
}
