import type {Mode} from '@github-ui/control-group'
import {appendToQuery} from '@github-ui/filter-query'
import {orgRepositoriesPath} from '@github-ui/paths'
import type React from 'react'

import {MatchingRepositoriesCount} from '../components/MatchingRepositoriesCount'
import {DynamicReposPicker} from '../DynamicReposPicker'
import {MultiSelectReposPicker} from '../MultiSelectReposPicker'

const all = {
  name: 'all',
  label: 'All repositories',
  description: 'Include all current and future repositories',
}

interface BuildMultipleProps extends React.ComponentProps<typeof MultiSelectReposPicker> {
  name?: string
}

function buildMultiple({name, ...pickerProps}: BuildMultipleProps): Mode {
  return {
    name: name || 'multiple',
    label: 'Only selected repositories',
    description: 'Applies only to specifically selected repositories',
    renderEditor: ({shouldOpen, labelId, descriptionId}) => (
      <MultiSelectReposPicker
        {...pickerProps}
        isOpenInitially={shouldOpen}
        aria-describedby={`${labelId} ${descriptionId}`}
      />
    ),
    editorDescription: null,
  }
}

interface BuildFilterProps extends React.ComponentProps<typeof DynamicReposPicker> {
  name?: string
}

function buildFilter({name, ...pickerProps}: BuildFilterProps): Mode {
  const {
    query = '',
    scope: {visibility},
  } = pickerProps

  const urlQuery = visibility ? appendToQuery(query, {visibility}) : query

  return {
    name: name || 'filter',
    label: 'Repositories matching a filter',
    description: 'Applies to repositories that match now and in the future',
    renderEditor: ({shouldOpen, labelId, descriptionId}) => (
      <DynamicReposPicker
        {...pickerProps}
        isOpenInitially={shouldOpen}
        aria-describedby={`${labelId} ${descriptionId}`}
      />
    ),
    editorDescription: ['organization', 'user'].includes(pickerProps.scope.type) ? (
      <MatchingRepositoriesCount
        scope={pickerProps.scope}
        query={query}
        href={
          pickerProps.scope.type === 'organization'
            ? orgRepositoriesPath({owner: pickerProps.scope.slug, query: urlQuery})
            : undefined
        }
      />
    ) : null,
  }
}

export const modes = {all, buildMultiple, buildFilter}
