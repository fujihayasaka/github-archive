import {BulkIssueMilestonePicker, MilestoneFragment} from '@github-ui/item-picker/MilestonePicker'
import type {
  MilestonePickerMilestone$key,
  MilestonePickerMilestone$data,
} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'
import {MilestoneIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, Button} from '@primer/react'
import {useCallback, useMemo} from 'react'
import {graphql, readInlineData, useLazyLoadQuery} from 'react-relay'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import {SPECIAL_VALUES} from '@github-ui/item-picker/Placeholders'
import type {ApplyMilestoneActionQuery} from './__generated__/ApplyMilestoneActionQuery.graphql'
import type {SharedListHeaderActionProps} from './ListItemsHeader'
import type {ExtendedItemProps} from '@github-ui/item-picker/ItemPicker'

type ApplyMilestoneActionProps = {
  issueIds: string[]
} & SharedListHeaderActionProps

export const ApplyMilestoneQuery = graphql`
  query ApplyMilestoneActionQuery($ids: [ID!]!) {
    nodes(ids: $ids) {
      ... on Issue {
        id
        milestone {
          # It is used but by readInlineData
          # eslint-disable-next-line relay/must-colocate-fragment-spreads
          ...MilestonePickerMilestone
        }
      }
    }
  }
`

export const ApplyMilestoneAction = ({
  issueIds,
  disabled,
  useQueryForAction,
  nested,
  singleKeyShortcutsEnabled,
  ...rest
}: ApplyMilestoneActionProps) => {
  const {nodes: updatedIssueNodes} = useLazyLoadQuery<ApplyMilestoneActionQuery>(
    ApplyMilestoneQuery,
    {ids: issueIds},
    {fetchPolicy: 'store-only'},
  )

  const selectedIssuesMilestones =
    (updatedIssueNodes || []).map(node => {
      const nodeId = node?.id
      if (!nodeId) return null
      const data =
        // eslint-disable-next-line no-restricted-syntax
        node.milestone ? readInlineData<MilestonePickerMilestone$key>(MilestoneFragment, node.milestone) : null

      return data
    }) ?? []

  // If all selected issues have the same milestone, mark this milestone as selected in the picker.
  const activeMilestone =
    selectedIssuesMilestones.length > 0 &&
    selectedIssuesMilestones.every(milestone => milestone?.id === selectedIssuesMilestones[0]?.id)
      ? selectedIssuesMilestones[0] || null
      : null

  const anchorElement = useCallback(
    (anchorProps: React.HTMLAttributes<HTMLElement>) => {
      const anchorText = 'Milestone'

      if (nested) {
        return (
          <ActionList.Item disabled={disabled} {...anchorProps} role="menuitem">
            <ActionList.LeadingVisual>
              <MilestoneIcon />
            </ActionList.LeadingVisual>
            {anchorText}
          </ActionList.Item>
        )
      }

      return (
        <Button
          data-testid={'bulk-set-milestone-button'}
          disabled={disabled}
          leadingVisual={MilestoneIcon}
          trailingVisual={TriangleDownIcon}
          {...anchorProps}
        >
          {anchorText}
        </Button>
      )
    },
    [disabled, nested],
  )

  const noMilestoneItem = useMemo(() => {
    const option: ExtendedItemProps<MilestonePickerMilestone$data> = {
      id: SPECIAL_VALUES.noMilestoneData.id,
      description: '',
      descriptionVariant: 'inline',
      children: <SafeHTMLText html={SPECIAL_VALUES.noMilestoneData.title as SafeHTMLString} />,
      source: SPECIAL_VALUES.noMilestoneData as MilestonePickerMilestone$data,
      groupId: '',
      leadingVisual: () => <MilestoneIcon />,
    }
    return option
  }, [])

  return (
    <BulkIssueMilestonePicker
      readonly={false}
      shortcutEnabled={singleKeyShortcutsEnabled}
      activeMilestone={activeMilestone}
      anchorElement={anchorElement}
      useQueryForAction={useQueryForAction}
      nested={nested}
      noMilestoneItem={noMilestoneItem}
      {...rest}
    />
  )
}
