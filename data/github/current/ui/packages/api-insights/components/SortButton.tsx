import {SortDescIcon, SortAscIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useReplaceSearchParams} from '../hooks/UseReplaceSearchParams'

import {clsx} from 'clsx'
import styles from './SortButton.module.css'

export interface SortButtonProps {
  title: string
  query_param: string
  clear_query_params?: string[]
}

// eslint-disable-next-line @eslint-react/no-unstable-default-props
export function SortButton({title, query_param, clear_query_params = []}: SortButtonProps) {
  const {searchParams, replaceSearchParams} = useReplaceSearchParams()
  const currentValue = searchParams.get(query_param) || 'no_sort'
  const currentIcon = currentValue === 'desc' || currentValue === 'no_sort' ? SortDescIcon : SortAscIcon

  const toggleSort = () => {
    const value = currentValue !== 'desc' ? 'desc' : 'asc'
    const params: {[key: string]: string} = clear_query_params.reduce((acc, param) => {
      return Object.assign(acc, {[param]: ''})
    }, {})
    params[query_param] = value
    replaceSearchParams(params)
  }
  return (
    <Button
      onClick={toggleSort}
      className={clsx(styles.sortButton, currentValue !== 'no_sort' && styles.hasSort, 'fgColor-muted f6 px-0')}
      trailingVisual={currentIcon}
      variant="invisible"
    >
      {title}
    </Button>
  )
}
