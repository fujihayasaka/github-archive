import {useConfirm} from '@primer/react'
import {useCallback} from 'react'

import {FileExport} from '../api/stats/contracts'
import {useSearch} from '../components/filter-bar/search-context'
import {useCopyPaste} from '../components/react_table/hooks/use-copy-paste'
import {ContentType} from '../platform/content-type'
import {useProjectDetails} from '../state-providers/memex/use-project-details'
import {useMemexItems} from '../state-providers/memex-items/use-memex-items'
import {usePostStats} from './common/use-post-stats'
import {useEnabledFeatures} from './use-enabled-features'
import {useViews} from './use-views'

const escapeFileName = (str: string) => str.replace(/[\\/:"*?<>|]/g, '')

export const useDownloadView = () => {
  const {itemsToCsv} = useCopyPaste()
  const {currentView} = useViews()
  const {matchesSearchQuery} = useSearch()
  const {items} = useMemexItems()
  const projectName = useProjectDetails().title
  const {postStats} = usePostStats()
  const confirm = useConfirm()
  const {memex_table_without_limits} = useEnabledFeatures()

  return useCallback(async () => {
    if (!currentView) return

    const visibleItems = memex_table_without_limits ? [...items] : items.filter(item => matchesSearchQuery(item))
    const content = itemsToCsv(visibleItems, {withHeaders: true})
    if (!content) return

    const shouldExport =
      !memex_table_without_limits ||
      (await confirm({
        title: 'Export view data',
        content: 'Only rows that have been loaded into this view will be exported.',
        confirmButtonContent: 'Export',
        confirmButtonType: 'primary',
      }))

    if (shouldExport) {
      postStats({name: FileExport, number_of_rows: visibleItems.length})

      const name = `${escapeFileName(projectName)} - ${escapeFileName(currentView.name)}.tsv`
      const blob = new Blob([content], {
        type: ContentType.CSV,
      })

      const url = URL.createObjectURL(blob)

      const a = document.createElement('a')
      a.style.display = 'none'
      a.href = url
      a.download = name
      document.body.appendChild(a)
      a.click()

      document.body.removeChild(a)
      window.URL.revokeObjectURL(url)
    }
  }, [currentView, items, itemsToCsv, matchesSearchQuery, projectName, postStats, confirm, memex_table_without_limits])
}
