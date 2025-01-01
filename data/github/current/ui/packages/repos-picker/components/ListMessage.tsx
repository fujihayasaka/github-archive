import type {UseQueryResult} from '@github-ui/react-query'
import type {PropsWithChildren} from 'react'

import type {FetchRepositoriesData, PickerRepository} from '../types'

export function ListMessage({children}: PropsWithChildren) {
  return <div className="m-6 p-6 text-center">{children}</div>
}

export function getBlankMessage(
  {isLoading, isError}: UseQueryResult<FetchRepositoriesData>,
  visibleItems: PickerRepository[],
): string {
  if (isLoading) {
    return 'Loading repositories...'
  }

  if (isError) {
    return 'Error loading repositories.'
  }

  if (visibleItems.length === 0) {
    return 'No repositories to show.'
  }

  return ''
}
