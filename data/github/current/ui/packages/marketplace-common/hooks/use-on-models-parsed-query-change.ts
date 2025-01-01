import {useCallback} from 'react'
import type {SearchResults} from '../types'
import {
  getValidPublisherFromParsedQuery,
  getValidCategoryFromParsedQuery as getValidModelsCategoryFromParsedQuery,
  getValidSortFromParsedQuery as getValidModelsSortFromParsedQuery,
  getValidTaskFromParsedQuery,
} from '../utilities/model-filter-options'
import {useCategory} from '../contexts/CategoryContext'
import {useModelsTask} from '../contexts/ModelsTaskContext'
import {useModelsPublisher} from '../contexts/ModelsPublisherContext'
import {useSort} from '../contexts/SortContext'

export function useOnModelsParsedQueryChange() {
  const {setCategory} = useCategory()
  const {setTask} = useModelsTask()
  const {setPublisher} = useModelsPublisher()
  const {setSort} = useSort()

  const onModelsParsedQueryChange = useCallback(
    (parsedQuery: SearchResults['parsedQuery']) => {
      const categoryFromParsedQuery = getValidModelsCategoryFromParsedQuery(parsedQuery)
      if (categoryFromParsedQuery) setCategory(categoryFromParsedQuery)

      const taskFromParsedQuery = getValidTaskFromParsedQuery(parsedQuery)
      if (taskFromParsedQuery) setTask(taskFromParsedQuery)

      const publisherFromParsedQuery = getValidPublisherFromParsedQuery(parsedQuery)
      if (publisherFromParsedQuery) setPublisher(publisherFromParsedQuery)

      const sortFromParsedQuery = getValidModelsSortFromParsedQuery(parsedQuery)
      if (sortFromParsedQuery) setSort(sortFromParsedQuery)
    },
    [setCategory, setPublisher, setSort, setTask],
  )

  return onModelsParsedQueryChange
}
