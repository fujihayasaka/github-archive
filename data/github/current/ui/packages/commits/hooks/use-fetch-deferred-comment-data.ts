import type {Repository} from '@github-ui/current-repository'
import {getInsightsUrl, reportTraceData} from '@github-ui/internal-api-insights'
import {commitCommentDeferredCommentDataPath} from '@github-ui/paths'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useEffect, useState} from 'react'

import type {CommentThreadData} from '../contexts/InlineCommentsContext'
import type {BaseCommit, FetchRequestState} from '../shared/types'
import type {CommitComment} from '../types/commit-types'

export type DeferredCommentData = {
  threadMarkers: CommentThreadData[]
  discussionComments: {
    comments: CommitComment[]
    count: number
    canLoadMore: boolean
  }
  subscribed: boolean
}

export function useDeferredCommentData(repo: Repository, commitOid: BaseCommit['oid']) {
  const [deferredData, setDeferredData] = useState<DeferredCommentData | undefined>(undefined)
  const [state, setState] = useState<FetchRequestState>('initial')

  useEffect(() => {
    setDeferredData(undefined)
    setState('loading')

    const hash = ssrSafeWindow?.location.hash

    let untilCommentId: string | undefined
    if (hash && /^#commitcomment-\d+$/.test(hash)) {
      untilCommentId = hash.replace('#commitcomment-', '')
    }

    const fetchDeferredData = async () => {
      const deferredCommentData = await fetchDeferredCommentData({repo, commitOid, untilCommentId})

      setDeferredData(deferredCommentData)
      setState('loaded')
    }

    fetchDeferredData()
  }, [commitOid, repo])

  return {
    deferredCommentData: deferredData,
    state,
  }
}

export async function fetchDeferredCommentData({
  repo,
  commitOid,
  untilCommentId,
}: {
  repo: Repository
  commitOid: BaseCommit['oid']
  untilCommentId?: string
}) {
  const response = await reactFetchJSON(
    getInsightsUrl(
      commitCommentDeferredCommentDataPath({
        owner: repo.ownerLogin,
        repo: repo.name,
        commitOid,
        untilCommentId,
      }),
    ),
  )

  if (response.ok) {
    const data: DeferredCommentData = await response.json()
    reportTraceData(data)
    return data
  } else {
    throw new Error('Failed to fetch comment data')
  }
}
