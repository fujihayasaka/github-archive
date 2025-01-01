import type {Comment, DiffLine, Thread} from '../types'
import {DiffAnnotationLevels, type DiffAnnotation, type MarkerNavigationImplementation} from '@github-ui/conversations'
import {noop} from '@github-ui/noop'

export function mockUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0
    const v = c === 'x' ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}

type BuildDiffLineInput = Partial<
  Omit<DiffLine, 'threads'> & {
    annotations: DiffAnnotation[]
    threads: Thread[]
    threadConnectionId?: string
    totalCommentsCount?: number
  }
>

export function buildDiffLine({
  blobLineNumber,
  left,
  right,
  html = '@@ -1,15 +1,15 @@',
  text = '@@ -1,15 +1,15 @@',
  displayNoNewLineWarning = false,
  threads = [],
  annotations = [],
  type = 'INJECTED_CONTEXT',
  threadConnectionId = mockUUID(),
  totalCommentsCount,
  __id,
}: BuildDiffLineInput): DiffLine {
  totalCommentsCount = totalCommentsCount ?? threads.flatMap(thread => thread.commentsData.comments ?? []).length
  return {
    left: left || blobLineNumber,
    right: right || blobLineNumber,
    blobLineNumber,
    displayNoNewLineWarning,
    html,
    text,
    type,
    __id: __id || mockUUID(),
    threadsData: {threads, __id: threadConnectionId, totalCommentsCount, totalCount: threads.length},
    annotationsData: {annotations, totalCount: annotations.length},
  } as DiffLine
}

type ThreadInput = Partial<Omit<Thread, 'commentsData'>> & {
  comments: Comment[]
  diffSide?: 'LEFT' | 'RIGHT'
}

export function buildThread({
  comments,
  id,
  isOutdated,
  diffSide,
  line,
  startDiffSide,
  startLine,
}: Partial<ThreadInput>) {
  return {
    commentsData: {comments: comments ?? [], totalCount: comments?.length ?? 0},
    id: id ?? mockUUID(),
    isOutdated: isOutdated ?? false,
    diffSide: diffSide ?? 'LEFT',
    line: line ?? 1,
    startDiffSide,
    startLine,
  }
}

export function buildComment({author, id}: Partial<Comment>) {
  return {
    author: author ?? {avatarUrl: '', login: 'mona', url: '/mona'},
    id: id ?? 1,
  }
}

export const mockMarkerNavigationImplementation: MarkerNavigationImplementation = {
  incrementActiveMarker: noop,
  decrementActiveMarker: noop,
  filteredMarkers: [],
  onActivateGlobalMarkerNavigation: noop,
  activeGlobalMarkerID: undefined,
}

type AnnotationInput = {[K in keyof DiffAnnotation]?: DiffAnnotation[K]}

export function buildAnnotation(data: AnnotationInput): DiffAnnotation {
  return {
    id: data.id ?? mockUUID(),
    annotationLevel: data.annotationLevel ?? DiffAnnotationLevels.Warning,
    startLine: data.startLine ?? 1,
    databaseId: data.databaseId ?? 123456,
    endLine: data.endLine ?? 1,
    message: data.message ?? 'message',
    path: data.path ?? 'my-file-path',
    pathDigest: data.pathDigest ?? mockUUID(),
    title: data.title ?? 'annotation-title',
    checkRun: {
      name: data.checkRun?.name ?? 'check-run-name',
      detailsUrl: data.checkRun?.detailsUrl ?? 'http://github.localhost/monalisa/smile/actions/runs/1/job/1',
    },
    checkSuiteName: data.checkSuiteName ?? 'check-suite-name',
    appAvatarUrl: data.appAvatarUrl ?? 'http://alambic.github.localhost/avatars/u/2',
    appAvatarAltText: data.appAvatarAltText ?? 'github-app',
  }
}
