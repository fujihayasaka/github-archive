import {type QuerySegment, tokenizeQuery} from '@github-ui/filter-query'
import React from 'react'

import styles from './TokenizedQuery.module.css'

export function TokenizedQuery({query}: {query: string}) {
  const segments = tokenizeQuery(query)

  return (
    <div className="d-flex gap-1 flex-wrap">
      {segments.map(segment => {
        if (segment.type === 'text') {
          return <span key={segment.value}>{segment.value}</span>
        } else {
          return <FilterToken key={segment.raw} segment={segment} />
        }
      })}
    </div>
  )
}

function FilterToken({segment}: {segment: Extract<QuerySegment, {type: 'filter'}>}) {
  return (
    <span>
      {segment.isNegated ? '-' : ''}
      {segment.key}:
      {segment.values.map((value, index) => (
        <React.Fragment key={`${segment.key}-${value}`}>
          {index > 0 && ','}
          <span className={styles.Token}>{value}</span>
        </React.Fragment>
      ))}
    </span>
  )
}
