import {MentionIcon, PersonIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, Button} from '@primer/react'
import type React from 'react'
import {useCallback, useMemo} from 'react'
import {searchUrl} from '@github-ui/issue-url-helper'
import {getTokensByType, replaceTokensDifferentially} from '../../../utils/urls'
import type {FilterBarPickerProps} from './ListItemsHeaderWithoutBulkActions'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import type {AssigneePickerAssignee$data} from '@github-ui/item-picker/AssigneePicker.graphql'
import {SPECIAL_VALUES} from '@github-ui/item-picker/Placeholders'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'
import type {ExtendedItemProps} from '@github-ui/item-picker/ItemPicker'
import {LABELS} from '../../../constants/labels'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../../types/app-payload'
import {AssigneeRepositoryPicker, type Assignee} from '@github-ui/item-picker/AssigneePicker'
import {formatActorLogin} from '@github-ui/item-picker/utils/assignee-picker'

export function ListAssigneeFilter({repo: scopedRepo, applySectionFilter, nested}: FilterBarPickerProps) {
  const {name: repo, owner} = scopedRepo
  const {activeSearchQuery, currentViewId} = useQueryContext()
  const {debouncedDirtySearchQuery} = useQueryEditContext()
  const {current_user_settings} = useAppPayload<AppPayload>()

  const query = debouncedDirtySearchQuery ?? activeSearchQuery

  const currentAssigneeTokens = useMemo(() => {
    const tokens = getTokensByType(query, 'assignee')

    // We want to specifically only show the last assignee token in the filter bar, as this is a single select variant picker and it's unable to show
    // multiple values. This is a workaround until we have a better solution for this.
    // Tracking issue here: https://github.com/github/issues/issues/11863
    return tokens.slice(-1)
  }, [query])

  const noAssigneeOption = useMemo(() => {
    const option: ExtendedItemProps<AssigneePickerAssignee$data> = {
      id: SPECIAL_VALUES.noAssigneeData.id,
      description: '',
      descriptionVariant: 'inline',
      children: <SafeHTMLText html={SPECIAL_VALUES.noAssigneeData.login as SafeHTMLString} />,
      source: SPECIAL_VALUES.noAssigneeData as AssigneePickerAssignee$data,
      selected: query.includes('no:assignee'),
      leadingVisual: () => <PersonIcon />,
    }
    return option
  }, [query])

  const onSelectionChanged = useCallback(
    (selectedAssignees: Assignee[]) => {
      const assignees = selectedAssignees.map(assignee => {
        if (assignee.id === SPECIAL_VALUES.noAssigneeData.id) {
          return 'no:assignee'
        }
        return formatActorLogin(assignee)
      })

      const newQuery = replaceTokensDifferentially(query, assignees, 'assignee')
      const url = searchUrl({viewId: currentViewId, query: newQuery})
      applySectionFilter(newQuery, url)
    },
    [query, applySectionFilter, currentViewId],
  )

  const props = {
    readonly: false,
    title: LABELS.filters.assigneesLabel,
    assigneeTokens: currentAssigneeTokens,
    assignees: [],
    repo,
    owner,
    onSelectionChange: onSelectionChanged,
    shortcutEnabled: current_user_settings?.use_single_key_shortcut || false,
    noAssigneeOption,
    anchorElement: nested ? NestedAssigneesAnchor : AssigneesAnchor,
    showNoMatchItem: true,
  }

  return (
    <AssigneeRepositoryPicker
      {...props}
      name="assignee"
      selectionVariant="single"
      includeAuthorableBots={false}
      includeAssignableBots
    />
  )
}

function NestedAssigneesAnchor(props: React.HTMLAttributes<HTMLElement>) {
  return (
    <ActionList.Item {...props} aria-label={LABELS.filters.assigneesLabel} role="menuitem">
      <ActionList.LeadingVisual>
        <MentionIcon />
      </ActionList.LeadingVisual>
      {LABELS.filters.assignees}...
    </ActionList.Item>
  )
}

function AssigneesAnchor(props: React.HTMLAttributes<HTMLButtonElement>) {
  return (
    <Button
      variant="invisible"
      sx={{
        color: 'fg.muted',
        width: 'fit-content',
      }}
      data-testid="assignees-anchor-button"
      trailingVisual={TriangleDownIcon}
      aria-label={LABELS.filters.assigneesLabel}
      {...props}
    >
      {LABELS.filters.assignees}
    </Button>
  )
}
