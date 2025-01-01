import {useEffect, useMemo} from 'react'
import {graphql, useFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'

import {VALUES} from '../../constants/values'
import useKnownShortcuts from '../../hooks/use-known-views'
import {useViewsNav} from '../../hooks/viewsNav'
import type {SavedViewRoute} from '../../types/views-types'
import type {SavedViewsQuery} from './__generated__/SavedViewsQuery.graphql'
import {CreateSavedView} from './CreateSavedView'
import {SavedViewRow} from './SavedViewRow'
import {NavList} from '@primer/react'
import {LABELS} from '../../constants/labels'
import classes from './SavedViews.module.css'
import type {SavedViewsShortcutsFragment$key} from './__generated__/SavedViewsShortcutsFragment.graphql'
import {useQueryContext} from '../../contexts/QueryContext'

export const SavedViewsGraphqlQuery = graphql`
  query SavedViewsQuery {
    viewer {
      dashboard {
        ...SavedViewsShortcutsFragment
      }
    }
  }
`

type SavedViewsProps = {
  savedViewsRef: PreloadedQuery<SavedViewsQuery>
}
type SavedViewsInternalProps = {
  savedViewsRef: SavedViewsShortcutsFragment$key
}

export function SavedViews({savedViewsRef}: SavedViewsProps) {
  const preloadedData = usePreloadedQuery<SavedViewsQuery>(SavedViewsGraphqlQuery, savedViewsRef)
  return preloadedData.viewer.dashboard ? <SavedViewsInternal savedViewsRef={preloadedData.viewer.dashboard} /> : null
}

function SavedViewsInternal({savedViewsRef}: SavedViewsInternalProps) {
  const {knownViews} = useKnownShortcuts()
  const {setSavedViewsCount} = useQueryContext()

  const shortcutData = useFragment(
    graphql`
      fragment SavedViewsShortcutsFragment on UserDashboard {
        shortcuts(first: 25) {
          totalCount
          nodes {
            id
            name
            query
            ...SavedViewRow
          }
        }
      }
    `,
    savedViewsRef,
  )

  const savedViews = useMemo(() => shortcutData.shortcuts.nodes || [], [shortcutData.shortcuts.nodes])

  useEffect(() => {
    setSavedViewsCount(shortcutData.shortcuts.totalCount)
  }, [shortcutData, setSavedViewsCount])

  const savedViewRoutes: SavedViewRoute[] = useMemo(
    () =>
      savedViews.filter(isDefined).map((view, index) => {
        return {
          id: view.id,
          name: view.name,
          query: view.query,
          position: index + knownViews.length + 1,
        }
      }),
    [knownViews.length, savedViews],
  )

  const viewKeys = useMemo(() => savedViewRoutes?.map(route => route.position.toString()), [savedViewRoutes])
  useViewsNav(savedViewRoutes, viewKeys, knownViews.length)

  return (
    <>
      <div className={`d-flex flex-items-center ${classes.headerRow}`}>
        <span className="flex-1">{LABELS.viewsTitle}</span>
        <CreateSavedView disabled={savedViews.length >= VALUES.viewsPageSize} />
      </div>
      <NavList aria-label={LABELS.viewsTitle} className={classes.savedViewsList}>
        {savedViews.length > 0 &&
          savedViews
            .filter(isDefined)
            .map((savedView, index) => <SavedViewRow key={savedView.id} savedView={savedView} position={index + 1} />)}
      </NavList>
    </>
  )
}

function isDefined<T>(value: T | undefined | null): value is T {
  return value !== undefined && value !== null
}
