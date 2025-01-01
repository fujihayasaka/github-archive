import {Heading, Spinner} from '@primer/react'

import type {DiffCategory, GroupedDiffs} from '../../utilities/diff-analysis'
import {compareDiffCategories, toSentenceCase} from '../../utilities/diff-analysis'
import {OverviewDiff} from './OverviewDiff'

export function OverviewDiffs({diffs, isLoading}: {diffs?: GroupedDiffs; isLoading?: boolean}) {
  if (isLoading) {
    return (
      <div className="d-flex flex-items-center flex-justify-center">
        <Spinner />
      </div>
    )
  }

  if (!diffs) return null

  return (
    <div className="d-flex flex-column gap-3">
      <Heading as="h2" className="f4">
        Files changed
      </Heading>
      {(Object.keys(diffs) as DiffCategory[]).sort(compareDiffCategories).map((category: DiffCategory) => {
        const diffsForCategory = diffs[category]
        if (!diffsForCategory?.length) return null

        return (
          <div key={category} className="d-flex flex-column gap-2">
            <Heading as="h3" className="f5">
              {toSentenceCase(category)}
            </Heading>
            <div className="d-flex flex-column gap-2">
              {diffsForCategory.map(diff => (
                <OverviewDiff key={diff.path} diff={diff} />
              ))}
            </div>
          </div>
        )
      })}
    </div>
  )
}
