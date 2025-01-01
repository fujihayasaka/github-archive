import {MilestonePicker} from '@github-ui/item-picker/MilestonePicker'
import {MilestoneIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, Button} from '@primer/react'
import type {FilterBarPickerProps} from './ListItemsHeaderWithoutBulkActions'
import {searchUrl} from '@github-ui/issue-url-helper'
import {getTokensByType, replaceAllFiltersByTypeInSearchQuery} from '../../../utils/urls'
import type {MilestonePickerMilestone$data} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {TEST_IDS} from '../../../constants/test-ids'
import {LABELS} from '../../../constants/labels'
import {SPECIAL_VALUES} from '@github-ui/item-picker/Placeholders'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import type {ExtendedItemProps} from '@github-ui/item-picker/ItemPicker'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../../types/app-payload'

export const ListMilestoneFilter = ({nested, repo, applySectionFilter}: FilterBarPickerProps) => {
  const {activeSearchQuery, currentViewId} = useQueryContext()
  const {debouncedDirtySearchQuery} = useQueryEditContext()
  const {current_user_settings} = useAppPayload<AppPayload>()
  const [activeMilestone, setActiveMilestone] = useState<MilestonePickerMilestone$data | null>(null)

  const query = debouncedDirtySearchQuery ?? activeSearchQuery

  const NoMilestoneItem = useMemo(() => {
    const option: ExtendedItemProps<MilestonePickerMilestone$data> = {
      id: SPECIAL_VALUES.noMilestoneData.id,
      description: '',
      descriptionVariant: 'inline',
      children: <SafeHTMLText html={SPECIAL_VALUES.noMilestoneData.title as SafeHTMLString} />,
      source: SPECIAL_VALUES.noMilestoneData as MilestonePickerMilestone$data,
      groupId: '',
      selected: query.includes('no:milestone'),
      leadingVisual: () => <MilestoneIcon />,
    }
    return option
  }, [query])

  // Check if there are any milestone tokens in the query, we only support one selection at this time
  // so default to the first one. Without updates to the filter, we cannot prevent the user from doing this manually.
  const currentMilestoneTokens = useMemo(() => {
    const tokens = getTokensByType(query, 'milestone')
    return tokens
  }, [query])

  // If the query doesn't have a milestone token, clear the active milestone
  useEffect(() => {
    if (currentMilestoneTokens.length <= 0) {
      setActiveMilestone(null)
    }
  }, [currentMilestoneTokens])

  const onSelectionChanged = useCallback(
    (selectedMilestones: MilestonePickerMilestone$data[]) => {
      const isNegatedFilter = selectedMilestones[0]?.id === SPECIAL_VALUES.noMilestoneData.id
      const milestones = selectedMilestones.map(milestone => milestone.title)

      if (selectedMilestones[0]) {
        setActiveMilestone(selectedMilestones[0])
      }

      const newQuery = replaceAllFiltersByTypeInSearchQuery(query, milestones, 'milestone', isNegatedFilter)
      const url = searchUrl({viewId: currentViewId, query: newQuery})
      applySectionFilter(newQuery, url)
    },
    [query, applySectionFilter, currentViewId],
  )

  return (
    <MilestonePicker
      repo={repo.name}
      activeMilestone={activeMilestone}
      anchorElement={nested ? NestedMilestonesAnchor : MilestonesAnchor}
      shortcutEnabled={current_user_settings?.use_single_key_shortcut || false}
      owner={repo.owner}
      onSelectionChanged={onSelectionChanged}
      noMilestoneItem={NoMilestoneItem}
      title={LABELS.filters.milestonesLabel}
    />
  )
}

function NestedMilestonesAnchor(props: React.HTMLAttributes<HTMLElement>) {
  return (
    <ActionList.Item {...props} aria-label={LABELS.filters.milestonesLabel} role="menuitem">
      <ActionList.LeadingVisual>
        <MilestoneIcon />
      </ActionList.LeadingVisual>
      {LABELS.filters.milestones}...
    </ActionList.Item>
  )
}

function MilestonesAnchor(props: React.HTMLAttributes<HTMLButtonElement>) {
  return (
    <Button
      variant="invisible"
      sx={{
        color: 'fg.muted',
        width: 'fit-content',
      }}
      data-testid={TEST_IDS.milestoneAnchorFilter}
      trailingVisual={TriangleDownIcon}
      aria-label={LABELS.filters.milestonesLabel}
      {...props}
    >
      {LABELS.filters.milestones}
    </Button>
  )
}
