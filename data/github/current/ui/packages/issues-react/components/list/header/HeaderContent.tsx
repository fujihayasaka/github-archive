import {validateViewTitle} from '@github-ui/entity-validators'
import {LABELS} from '@github-ui/issue-viewer/Labels'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {IS_BROWSER, ssrSafeLocation} from '@github-ui/ssr-utils'
import {Box, FormControl, Heading, Text, TextInput} from '@primer/react'
import type React from 'react'
import {useEffect, useMemo, useRef, useState} from 'react'
import {graphql, useFragment} from 'react-relay'

import type {AppPayload} from '../../../types/app-payload'
import type {HeaderContentCurrentViewFragment$key} from './__generated__/HeaderContentCurrentViewFragment.graphql'
import {IconAndColorPicker} from './IconAndColorPicker'
import {MESSAGES} from '../../../constants/messages'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {ISSUES_INDEX_DEFAULT_TITLE, ISSUES_INDEX_QUICK_FILTERS} from '../../../constants/index-sidebar-constants'
import {isQueryMatchSearchInUrl} from '../../../utils/urls'
import {QUERIES} from '@github-ui/query-builder/constants/queries'
import {ViewOptionsButton} from './ViewOptionsButton'
import {isDirty} from '../../../utils/type-predicates'

type HeaderContentProps = {
  readOnly?: boolean
  currentViewKey: HeaderContentCurrentViewFragment$key
}

export function HeaderContent({readOnly = false, currentViewKey}: HeaderContentProps) {
  const {isCustomView, isEditing} = useQueryContext()
  const {scoped_repository} = useAppPayload<AppPayload>()

  const currentViewData = useFragment<HeaderContentCurrentViewFragment$key>(
    graphql`
      fragment HeaderContentCurrentViewFragment on Shortcutable {
        name
        description
        id
        ...IconAndColorPickerViewFragment
        ...ViewOptionsButtonCurrentViewFragment
      }
    `,
    currentViewKey,
  )

  const {name: viewName, description: viewDescription, id: viewId} = currentViewData

  const {dirtyTitle, setDirtyTitle, dirtyDescription, setDirtyDescription, shouldFocusSearchOnNav} =
    useQueryEditContext()
  const [titleValidationResult, setTitleValidationResult] = useState<string | undefined>(undefined)

  const viewTitleRef = useRef<HTMLInputElement>(null)

  const onTitleChange: React.ChangeEventHandler<HTMLInputElement> = e => {
    const inputTitle = e.target.value
    const inputValidationResult = validateViewTitle(inputTitle)
    setTitleValidationResult(inputValidationResult.errorMessage)
    setDirtyTitle(inputTitle)
  }

  const onDescriptionChange: React.ChangeEventHandler<HTMLInputElement> = e => {
    setDirtyDescription(e.target.value)
  }

  useEffect(() => {
    if (isEditing && viewTitleRef.current && IS_BROWSER && !shouldFocusSearchOnNav) {
      requestAnimationFrame(() => {
        if (viewTitleRef.current) {
          viewTitleRef.current.focus()
        }
      })
    }
  }, [isEditing, shouldFocusSearchOnNav])

  const indexQuickFiltersEnabled = isFeatureEnabled('issues_react_index_quick_filters')
  const {search} = ssrSafeLocation
  const title = useMemo(() => {
    if (!indexQuickFiltersEnabled) {
      return viewName
    }
    return (
      ISSUES_INDEX_QUICK_FILTERS.find(item =>
        isQueryMatchSearchInUrl({query: item.query, search, defaultQuery: QUERIES.defaultRepoLevelOpen}),
      )?.name ?? ISSUES_INDEX_DEFAULT_TITLE
    )
  }, [search, viewName, indexQuickFiltersEnabled])

  return (
    <Box sx={{width: 'auto', display: 'flex', alignItems: 'center', flex: 1}}>
      {isEditing ? (
        <Box sx={{width: '100%', display: 'flex', gap: 2, flexDirection: 'column'}}>
          <Box sx={{display: 'flex', flexDirection: 'row', gap: 2}}>
            <FormControl>
              <FormControl.Label htmlFor="edit-view-icon-button">{MESSAGES.icon}</FormControl.Label>
              {isCustomView(viewId) && <IconAndColorPicker readOnly={readOnly} currentView={currentViewData} />}
            </FormControl>
            <FormControl sx={{flexGrow: 1}}>
              <FormControl.Label>{MESSAGES.title}</FormControl.Label>
              <TextInput
                ref={viewTitleRef}
                onChange={onTitleChange}
                value={isDirty(dirtyTitle) ? dirtyTitle : title}
                placeholder={LABELS.viewTitlePlaceholder}
                sx={{width: '100%'}}
              />
              {titleValidationResult && (
                <FormControl.Validation variant="error">{titleValidationResult}</FormControl.Validation>
              )}
            </FormControl>
          </Box>
          <FormControl sx={{flexGrow: 1}}>
            <FormControl.Label>{MESSAGES.description}</FormControl.Label>
            <TextInput
              onChange={onDescriptionChange}
              value={isDirty(dirtyDescription) ? dirtyDescription : viewDescription}
              placeholder={LABELS.viewDescriptionPlaceholder}
              sx={{width: '100%'}}
            />
          </FormControl>
        </Box>
      ) : (
        <Box sx={{display: 'flex', gap: 1, flexDirection: 'column'}}>
          <Box as="span" sx={{alignItems: 'left', display: 'flex', flexDirection: 'row', gap: 2}}>
            {isCustomView(viewId) && <IconAndColorPicker readOnly={readOnly} currentView={currentViewData} />}
            <Heading
              as="h1"
              className={scoped_repository && !indexQuickFiltersEnabled ? 'sr-only' : ''}
              sx={{fontSize: 3}}
            >
              {title}
            </Heading>
            {isCustomView(viewId) && !readOnly && <ViewOptionsButton currentView={currentViewData} />}
          </Box>
          {viewDescription && <Text sx={{fontSize: 14, mr: 2, color: 'fg.muted'}}>{viewDescription}</Text>}
        </Box>
      )}
    </Box>
  )
}
