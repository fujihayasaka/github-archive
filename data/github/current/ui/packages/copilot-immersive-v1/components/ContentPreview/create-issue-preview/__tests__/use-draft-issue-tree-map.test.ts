import {renderHook} from '@github-ui/react-core/test-utils'

import {
  type DraftIssue,
  type PreviewableContent,
  type PreviewableContentIdentifier,
  stripVersionFromId,
} from '../../content-preview-types'
import {useDraftIssueTreeMap} from '../use-draft-issue-tree-map'

const mockContentPreviewContext = {
  items: new Map<PreviewableContentIdentifier, PreviewableContent>(),
  versionedItems: new Map<PreviewableContentIdentifier, PreviewableContentIdentifier[]>(),
}
jest.mock('../../../../components/ContentPreview/ContentPreviewContext', () => ({
  useContentPreview: jest.fn(() => mockContentPreviewContext),
}))

function createDraftIssue(tag: string, overrides?: Partial<DraftIssue>): DraftIssue {
  return {
    tag,
    id: `new-issue:${tag}#1` as const,
    ...overrides,
  } as DraftIssue
}

describe('useDraftIssueTreeMap', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockContentPreviewContext.items.clear()
    mockContentPreviewContext.versionedItems.clear()
  })

  it('returns a map of draft issues with their parent-child relationships', () => {
    const epic = createDraftIssue('epic')
    mockContentPreviewContext.items.set(epic.id, epic)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

    const feature = createDraftIssue('feature', {parentTag: epic.tag})
    mockContentPreviewContext.items.set(feature.id, feature)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(feature.id), [feature.id])

    const task = createDraftIssue('task', {parentTag: feature.tag})
    mockContentPreviewContext.items.set(task.id, task)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(task.id), [task.id])

    const {result} = renderHook(() => useDraftIssueTreeMap())

    expect(result.current.size).toBe(3)

    const epicNode = result.current.get(epic.tag)
    expect(epicNode).toBeDefined()
    expect(epicNode?.item).toEqual(epic)
    expect(epicNode?.children.length).toBe(1)
    expect(epicNode?.children?.[0]?.item).toEqual(feature)
    expect(epicNode?.parent).toBeNull()

    const featureNode = result.current.get(feature.tag)
    expect(featureNode).toBeDefined()
    expect(featureNode?.item).toEqual(feature)
    expect(featureNode?.children.length).toBe(1)
    expect(featureNode?.children?.[0]?.item).toEqual(task)
    expect(featureNode?.parent).toEqual(epicNode)

    const taskNode = result.current.get(task.tag)
    expect(taskNode).toBeDefined()
    expect(taskNode?.item).toEqual(task)
    expect(taskNode?.children.length).toBe(0)
    expect(taskNode?.parent).toEqual(featureNode)
  })

  it('returns an empty map when there are no preview items', () => {
    const {result} = renderHook(() => useDraftIssueTreeMap())
    expect(result.current.size).toBe(0)
  })

  it('returns an empty map when there are no draft issues', () => {
    const image = {type: 'image', id: 'image:foo' as const} as unknown as PreviewableContent
    mockContentPreviewContext.items.set(image.id, image)
    mockContentPreviewContext.versionedItems.set(image.id, [image.id])

    const {result} = renderHook(() => useDraftIssueTreeMap())
    expect(result.current.size).toBe(0)
  })

  it('handles missing entries in items', () => {
    const epic = createDraftIssue('epic')
    mockContentPreviewContext.items.set(epic.id, epic)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

    const feature = createDraftIssue('feature', {parentTag: epic.tag})
    // simulate break; feature issue is not in items
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(feature.id), [feature.id])

    const task = createDraftIssue('task', {parentTag: feature.tag})
    mockContentPreviewContext.items.set(task.id, task)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(task.id), [task.id])

    const {result} = renderHook(() => useDraftIssueTreeMap())

    expect(result.current.size).toBe(2)

    const epicNode = result.current.get(epic.tag)
    expect(epicNode).toBeDefined()
    expect(epicNode?.item).toEqual(epic)
    expect(epicNode?.children.length).toBe(0)
    expect(epicNode?.parent).toBeNull()

    const featureNode = result.current.get(feature.tag)
    expect(featureNode).toBeUndefined()

    const taskNode = result.current.get(task.tag)
    expect(taskNode).toBeDefined()
    expect(taskNode?.item).toEqual(task)
    expect(taskNode?.children.length).toBe(0)
    expect(taskNode?.parent).toBeNull()
  })

  it('handles missing entries in versionedItems', () => {
    const epic = createDraftIssue('epic')
    mockContentPreviewContext.items.set(epic.id, epic)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

    const feature = createDraftIssue('feature', {parentTag: epic.tag})
    mockContentPreviewContext.items.set(feature.id, feature)
    // simulate break; feature issue is not in versionedItems

    const task = createDraftIssue('task', {parentTag: feature.tag})
    mockContentPreviewContext.items.set(task.id, task)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(task.id), [task.id])

    const {result} = renderHook(() => useDraftIssueTreeMap())

    expect(result.current.size).toBe(2)

    const epicNode = result.current.get(epic.tag)
    expect(epicNode).toBeDefined()
    expect(epicNode?.item).toEqual(epic)
    expect(epicNode?.children.length).toBe(0)
    expect(epicNode?.parent).toBeNull()

    const featureNode = result.current.get(feature.tag)
    expect(featureNode).toBeUndefined()

    const taskNode = result.current.get(task.tag)
    expect(taskNode).toBeDefined()
    expect(taskNode?.item).toEqual(task)
    expect(taskNode?.children.length).toBe(0)
    expect(taskNode?.parent).toBeNull()
  })

  it('uses the latest version of each draft issue', () => {
    const featureV1 = createDraftIssue('feature', {id: `new-issue:feature#1`})
    const featureV2 = createDraftIssue('feature', {id: `new-issue:feature#2`})
    mockContentPreviewContext.items.set(featureV1.id, featureV1)
    mockContentPreviewContext.items.set(featureV2.id, featureV2)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(featureV1.id), [featureV1.id, featureV2.id])

    const taskV1 = createDraftIssue('task', {parentTag: featureV1.tag, id: `new-issue:task#1`})
    const taskV2 = createDraftIssue('task', {parentTag: featureV2.tag, id: `new-issue:task#2`})
    mockContentPreviewContext.items.set(taskV1.id, taskV1)
    mockContentPreviewContext.items.set(taskV2.id, taskV2)
    mockContentPreviewContext.versionedItems.set(stripVersionFromId(taskV1.id), [taskV1.id, taskV2.id])

    const {result} = renderHook(() => useDraftIssueTreeMap())

    expect(result.current.size).toBe(2)

    const featureNode = result.current.get(featureV1.tag)
    expect(featureNode).toBeDefined()
    expect(featureNode?.item).toEqual(featureV2)
    expect(featureNode?.children.length).toBe(1)
    expect(featureNode?.children?.[0]?.item).toEqual(taskV2)
    expect(featureNode?.parent).toBeNull()

    const taskNode = result.current.get(taskV1.tag)
    expect(taskNode).toBeDefined()
    expect(taskNode?.item).toEqual(taskV2)
    expect(taskNode?.children.length).toBe(0)
    expect(taskNode?.parent).toEqual(featureNode)
  })
})
