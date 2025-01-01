import type {SharedBulkActionsItemPickerProps} from '@github-ui/item-picker/ItemPicker'
import type {ReactElement, Suspense} from 'react'
import type {MilestoneIssuesList$data} from './__generated__/MilestoneIssuesList.graphql'

type ArrayElement<ArrayType extends readonly unknown[]> = ArrayType extends ReadonlyArray<infer ElementType>
  ? ElementType
  : never

type NodeType = NonNullable<NonNullable<ArrayElement<NonNullable<MilestoneIssuesList$data['search']['edges']>>>['node']>

type PullRequestNodeType = Extract<NodeType, {__typename: 'PullRequest'}>

export type IssueNodeType = Extract<NodeType, {__typename: 'Issue'}>
export type ItemNodeType = IssueNodeType | PullRequestNodeType

export type SharedListHeaderActionProps = {
  repo: string
  owner: string
  disabled: boolean
  singleKeyShortcutsEnabled: boolean
  /**
   * Whether to render the 'Add <property>' select panel as a nested select panel (true) versus a standalone select
   * panel (false; default).
   */
  nested?: boolean
} & SharedBulkActionsItemPickerProps

export type ScopedRepository = Pick<
  MilestoneIssuesList$data,
  'id' | 'name' | 'isDisabled' | 'viewerCanPush' | 'isLocked'
> & {
  owner: MilestoneIssuesList$data['owner']['login']
  // How to add this separetly because in ui/packages/list-view-items-issues-prs/components/IssueRow.tsx it is defined with underscore.
  is_archived: MilestoneIssuesList$data['isArchived']
}

export type ListItemsHeaderProps = {
  checkedItems: Map<string, ItemNodeType>
  issueCount: number
  issueNodes: ItemNodeType[]
  setCheckedItems: (checkedItems: Map<string, ItemNodeType>) => void
  updateListHasPRs: (checkedMap: Map<string, ItemNodeType>) => void
  // setReactionEmojiToDisplay: (arg: {reaction: string; reactionEmoji: string}) => void
  // setCurrentPage: (page: number) => void // currently pagination is not supported
  useBulkActions: boolean
  scopedRepository: ScopedRepository
  sectionFilters?: ReactElement<typeof Suspense> // ListViewSectionFilterLinks | ReactElement<typeof Suspense>
  singleKeyShortcutsEnabled?: boolean
  bulkJobId: string | null
  setBulkJobId: (bulkJobId: string | null) => void
  isInOrganization?: boolean
}
