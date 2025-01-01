import type {Thread} from '@github-ui/diff-lines'
import {noop} from '@github-ui/noop'
import type React from 'react'
import {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react'

import type {CommitComment} from '../types/commit-types'

type InlineCommentsContextType = {
  comments: CommitComment[]
  addComments: (comments: CommitComment[], path: string, position: string) => void
  findInlineComment: (commentDatabaseId: number | null | undefined) => CommitComment | undefined
  findInlineCommentWithRelay: (relayId: string) => CommitComment | undefined
  getCommentCountByPath: (path: string) => number
  getThreadDataByPathAndPosition: (path: string, position: number) => CommentThreadData | undefined
  getInlineCommentInfoByPathAndPosition: (path: string, position: number) => CommitComment[] | undefined
  updateInlineCommentMapWithNewComment: (
    path: string,
    position: number,
    commentArray: CommitComment[],
    shouldAppend: boolean,
  ) => void
  initialExpandedThreadId?: string
}

export type CommentThread = Pick<Thread, 'id' | 'commentsData' | 'diffSide'>

export type CommentThreadData = {
  path: string
  position: number
  count: number
  threads?: CommentThread[]
  inlineComments?: Record<number, CommitComment[]>
}

const InlineCommentsContext = createContext<InlineCommentsContextType>({
  comments: [],
  addComments: noop,
  findInlineComment: () => undefined,
  findInlineCommentWithRelay: () => undefined,
  getCommentCountByPath: () => 0,
  getThreadDataByPathAndPosition: () => undefined,
  updateInlineCommentMapWithNewComment: () => undefined,
  getInlineCommentInfoByPathAndPosition: () => undefined,
})

function arrayToMap(array: CommentThreadData[]) {
  return array.reduce((acc, thread) => {
    acc.set(`${thread.path}::${thread.position}`, thread)
    return acc
  }, new Map<string, CommentThreadData>())
}

function recordToMap(
  record: Record<string, Record<number, CommitComment[]>>,
): Map<string, Map<number, CommitComment[]>> {
  const map = new Map<string, Map<number, CommitComment[]>>()

  for (const path in record) {
    if (record.hasOwnProperty(path)) {
      const positionMap = new Map<number, CommitComment[]>()
      for (const position in record[path]) {
        if (record[path].hasOwnProperty(position)) {
          positionMap.set(Number(position), record[path][Number(position)]!)
        }
      }
      map.set(path, positionMap)
    }
  }

  return map
}

export function InlineCommentsProvider({
  children,
  initialFiles,
  initialExpandedThreadId,
  initialInlineComments,
}: React.PropsWithChildren<{
  initialInlineComments?: Record<string, Record<number, CommitComment[]>>
  initialFiles?: CommentThreadData[]
  initialExpandedThreadId?: string
}>) {
  const [comments, setComments] = useState<CommitComment[]>(() => {
    if (initialInlineComments) {
      return Object.values(initialInlineComments).flatMap(positionMap => Array.from(Object.values(positionMap).flat()))
    } else {
      return []
    }
  })
  const [commentThreadData, setCommentThreadData] = useState<CommentThreadData[]>(initialFiles ?? [])
  const [commentThreadDataMap, setCommentThreadDataMap] = useState<Map<string, CommentThreadData>>(() =>
    initialFiles ? arrayToMap(initialFiles) : new Map(),
  )
  const [inlineCommentThreadMap, setInlineCommentThreadMap] = useState<Map<string, Map<number, CommitComment[]>>>(() =>
    initialInlineComments ? recordToMap(initialInlineComments) : new Map(),
  )

  //takes an array which then replaces the inline comment thread map or appends itself to the end of the current
  //inline comment thread map based on the shouldAppend boolean
  const updateInlineCommentMapWithNewComment = useCallback(
    (path: string, position: number, commentArray: CommitComment[], shouldAppend: boolean) => {
      if (shouldAppend) {
        let positionArray = inlineCommentThreadMap.get(path)?.get(position) ?? []
        positionArray = positionArray.concat(commentArray)
        const positionMap = inlineCommentThreadMap.get(path)?.set(position, positionArray)
        setInlineCommentThreadMap(inlineCommentThreadMap.set(path, positionMap ?? new Map()) ?? inlineCommentThreadMap)
      } else {
        const positionMap = inlineCommentThreadMap.get(path)?.set(position, commentArray)
        setInlineCommentThreadMap(inlineCommentThreadMap.set(path, positionMap ?? new Map()) ?? inlineCommentThreadMap)
      }
    },
    [inlineCommentThreadMap],
  )

  useEffect(() => {
    setCommentThreadData(initialFiles ?? [])
    setCommentThreadDataMap(initialFiles ? arrayToMap(initialFiles) : new Map())
    //if we make this grab comments piece by piece in the future we will want to
    //do some logic to merge the initial comments with the new comments
    setInlineCommentThreadMap(initialInlineComments ? recordToMap(initialInlineComments) : new Map())
    setComments(
      initialInlineComments
        ? Object.values(initialInlineComments).flatMap(positionMap => Array.from(Object.values(positionMap).flat()))
        : [],
    )
  }, [initialFiles, initialInlineComments])

  const addComments = useCallback(
    (newComments: CommitComment[], path: string, position: string) => {
      const newCommentIds = newComments.map(comment => comment.id)
      const existingComments = comments.filter(comment => !newCommentIds.includes(comment.id))

      const unchangedThreads = commentThreadData.filter(
        thread => thread.path !== path || thread.position !== parseInt(position),
      )

      const threadToAdd: CommentThreadData = {
        path,
        position: parseInt(position),
        count: newComments.length,
        threads: [
          {
            id: `${path}::${position}`,
            diffSide: 'RIGHT',
            commentsData: {
              totalCount: newComments.length,
              comments: newComments.map(comment => {
                return {
                  id: comment.id,
                  author: {
                    avatarUrl: comment?.author?.avatarUrl ?? '',
                    login: comment?.author?.login ?? '',
                    url: '',
                  },
                }
              }),
            },
          },
        ],
      }

      setComments([...existingComments, ...newComments])
      setCommentThreadData([...unchangedThreads, threadToAdd])
      setCommentThreadDataMap(arrayToMap([...unchangedThreads, threadToAdd]))
      updateInlineCommentMapWithNewComment(path, parseInt(position), newComments, false)
    },
    [commentThreadData, comments, updateInlineCommentMapWithNewComment],
  )

  const findInlineComment = useCallback(
    (commentDatabaseId: number | null | undefined) => {
      if (!commentDatabaseId) return
      return comments.find(comment => comment.id === commentDatabaseId)
    },
    [comments],
  )

  const findInlineCommentWithRelay = useCallback(
    (id: string) => {
      return comments.find(comment => comment.relayId === id)
    },
    [comments],
  )

  const getCommentCountByPath = useCallback(
    (path: string) => {
      let count = 0

      for (const thread of commentThreadData) {
        if (thread.path === path) {
          count += thread.count
        }
      }

      return count
    },
    [commentThreadData],
  )

  const getThreadDataByPathAndPosition = useCallback(
    (path: string, position: number) => {
      return commentThreadDataMap.get(`${path}::${position}`)
    },
    [commentThreadDataMap],
  )
  const getInlineCommentInfoByPathAndPosition = useCallback(
    (path: string, position: number) => {
      return inlineCommentThreadMap.get(path)?.get(position)
    },
    [inlineCommentThreadMap],
  )

  const inlineComments = useMemo(
    () => ({
      comments,
      addComments,
      findInlineComment,
      findInlineCommentWithRelay,
      getCommentCountByPath,
      getThreadDataByPathAndPosition,
      getInlineCommentInfoByPathAndPosition,
      updateInlineCommentMapWithNewComment,
      initialExpandedThreadId,
    }),
    [
      addComments,
      comments,
      findInlineComment,
      findInlineCommentWithRelay,
      getCommentCountByPath,
      getThreadDataByPathAndPosition,
      getInlineCommentInfoByPathAndPosition,
      updateInlineCommentMapWithNewComment,
      initialExpandedThreadId,
    ],
  )

  return <InlineCommentsContext.Provider value={inlineComments}>{children}</InlineCommentsContext.Provider>
}

export function useInlineComments() {
  const context = useContext(InlineCommentsContext)

  if (!context) {
    throw new Error('useInlineComments must be used within a InlineCommentsProvider')
  }

  return context
}
