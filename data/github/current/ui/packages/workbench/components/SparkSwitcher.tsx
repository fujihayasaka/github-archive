import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {SparkleFillIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, RelativeTime, Spinner} from '@primer/react'
import {memo, useMemo} from 'react'

import {useWorkbenchContext, type WorkbenchContextData} from '../contexts/WorkbenchContext'
import type {Workbench} from '../types/workbench-types'
import styles from './SparkSwitcher.module.css'

export const SparkSwitcher = memo(() => {
  const workbench = useWorkbenchContext()

  const {data: sparks, isLoading} = useQuery({
    queryKey: ['sparks'],
    queryFn: async () => {
      const res = await verifiedFetchJSON('/copilot/spark/workbench', {method: 'GET'})
      if (!res.ok) throw new Error('Failed to fetch')
      const data = (await res.json()) as {workbenches: Workbench[]}
      return data.workbenches
    },
    select: data => {
      return data.reverse()
    },
  })

  const {sparkBaseUrl} = useWorkbenchContext()

  const displayedSparks = useMemo(() => {
    if (!sparks) return []
    // Filter out the current workbench and sort by updatedAt
    const filteredSparks = [
      workbench,
      ...sparks
        .filter(s => s.id !== workbench.id)
        .sort((a, b) => {
          if (!a.updatedAt) return -1
          if (!b.updatedAt) return 1
          return parseInt(a.updatedAt, 10) - parseInt(b.updatedAt, 10)
        })
        .slice(0, 4),
    ]

    return filteredSparks
  }, [sparks, workbench])

  // Handle spark selection
  const handleSparkChange = (spark: Workbench | WorkbenchContextData) => {
    // Redirect to the selected spark instead of keeping it in state
    window.location.assign(sparkBaseUrl(spark))
  }

  return (
    <ActionMenu>
      <ActionMenu.Button size="medium" variant="invisible">
        {workbench.name ?? ''}
      </ActionMenu.Button>
      {/* eslint-disable-next-line primer-react/no-system-props */}
      <ActionMenu.Overlay maxHeight="medium" width="small" maxWidth="medium" className={styles.sparkSwitcherOverlay}>
        <ActionList>
          <ActionList.Group selectionVariant="single">
            {isLoading || !displayedSparks ? (
              <ActionList.Item>
                <Spinner size="small" /> Loading sparks...
              </ActionList.Item>
            ) : displayedSparks.length === 0 ? (
              <ActionList.Item>No sparks available</ActionList.Item>
            ) : (
              displayedSparks.map(spark => (
                <ActionList.Item
                  key={spark.id}
                  selected={workbench.id === spark.id}
                  onSelect={() => handleSparkChange(spark)}
                >
                  {spark.name}
                  {spark.updatedAt && (
                    <ActionList.Description variant="block">
                      <RelativeTime date={new Date(spark.updatedAt)} />
                    </ActionList.Description>
                  )}
                </ActionList.Item>
              ))
            )}
          </ActionList.Group>
          <ActionList.Divider />
          <ActionList.Group>
            <ActionList.LinkItem href="/spark">
              <ActionList.LeadingVisual>
                <SparkleFillIcon />
              </ActionList.LeadingVisual>
              All sparks
            </ActionList.LinkItem>
          </ActionList.Group>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
})

SparkSwitcher.displayName = 'SparkSwitcher'
