import {useCallback} from 'react'
import type {SearchResults} from '../types'
import {useSearchType} from '../contexts/SearchTypeContext'
import {useOnModelsParsedQueryChange} from './use-on-models-parsed-query-change'

export function useOnParsedQueryChange() {
  const {type} = useSearchType()
  const onModelsParsedQueryChange = useOnModelsParsedQueryChange()

  const onParsedQueryChange = useCallback(
    (parsedQuery: SearchResults['parsedQuery']) => {
      if (type === 'models') onModelsParsedQueryChange(parsedQuery)
    },
    [onModelsParsedQueryChange, type],
  )

  return onParsedQueryChange
}
