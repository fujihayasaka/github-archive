import {PersonIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, Button} from '@primer/react'
import type React from 'react'
import {useCallback, useMemo} from 'react'
import {searchUrl} from '@github-ui/issue-url-helper'
import {getTokensByType, replaceAllFiltersByTypeInSearchQuery} from '../../../utils/urls'
import type {FilterBarPickerProps} from './ListItemsHeaderWithoutBulkActions'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import {LABELS} from '../../../constants/labels'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../../types/app-payload'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {AssigneeRepositoryPicker, type Assignee} from '@github-ui/item-picker/AssigneePicker'
import {formatActorLogin} from '@github-ui/item-picker/utils/assignee-picker'

export function ListAuthorFilter({repo: scopedRepo, applySectionFilter, nested}: FilterBarPickerProps) {
  const {name: repo, owner} = scopedRepo
  const {activeSearchQuery, currentViewId} = useQueryContext()
  const {debouncedDirtySearchQuery} = useQueryEditContext()
  const {current_user_settings} = useAppPayload<AppPayload>()
  const includeBots = isFeatureEnabled('issues_react_include_bots_in_pickers')

  const query = debouncedDirtySearchQuery ?? activeSearchQuery

  const currentAuthorTokens = useMemo(() => getTokensByType(query, 'author'), [query])

  const onSelectionChanged = useCallback(
    (selectedAuthors: Assignee[]) => {
      const authors = selectedAuthors.map(formatActorLogin)
      const newQuery = replaceAllFiltersByTypeInSearchQuery(query, authors, 'author')
      const url = searchUrl({viewId: currentViewId, query: newQuery})
      applySectionFilter(newQuery, url)
    },
    [query, applySectionFilter, currentViewId],
  )

  const props = {
    readonly: false,
    title: LABELS.filters.authorLabel,
    assigneeTokens: currentAuthorTokens,
    assignees: [],
    repo,
    owner,
    onSelectionChange: onSelectionChanged,
    shortcutEnabled: current_user_settings?.use_single_key_shortcut || false,
    anchorElement: nested ? NestedAuthorsAnchor : AuthorsAnchor,
    showNoMatchItem: true,
  }

  return (
    <AssigneeRepositoryPicker
      name="author"
      selectionVariant="single"
      {...props}
      includeAuthorableBots={includeBots}
      includeAssignableBots={false}
    />
  )
}

function NestedAuthorsAnchor(props: React.HTMLAttributes<HTMLElement>) {
  return (
    <ActionList.Item {...props} aria-label={LABELS.filters.authorLabel} role="menuitem">
      <ActionList.LeadingVisual>
        <PersonIcon />
      </ActionList.LeadingVisual>
      {LABELS.filters.author}...
    </ActionList.Item>
  )
}

function AuthorsAnchor(props: React.HTMLAttributes<HTMLButtonElement>) {
  return (
    <Button
      variant="invisible"
      sx={{
        color: 'fg.muted',
        width: 'fit-content',
      }}
      data-testid="authors-anchor-button"
      trailingVisual={TriangleDownIcon}
      aria-label={LABELS.filters.authorLabel}
      {...props}
    >
      {LABELS.filters.author}
    </Button>
  )
}
