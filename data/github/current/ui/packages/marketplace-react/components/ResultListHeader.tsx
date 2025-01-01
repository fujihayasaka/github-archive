import {useMemo} from 'react'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import {useQuery} from '@github-ui/marketplace-common/QueryContext'
import {useSearchType} from '@github-ui/marketplace-common/SearchTypeContext'
import {useCopilotApp} from '@github-ui/marketplace-common/CopilotAppContext'
import {useCategory} from '@github-ui/marketplace-common/CategoryContext'
import {useSearchResults} from '@github-ui/marketplace-common/SearchResultsContext'
import type {Category} from '@github-ui/marketplace-common'
import {ResultListHeader as ModelsResultListHeader} from '@github-ui/github-models/ResultListHeader'
import {testIdProps} from '@github-ui/test-id-props'

interface ResultListHeaderProps {
  categories: {
    apps: Category[]
    actions: Category[]
  }
}

export function ResultListHeader({categories}: ResultListHeaderProps) {
  const {category} = useCategory()
  const {query} = useQuery()
  const {copilotApp} = useCopilotApp()
  const {type} = useSearchType()
  const {searchResults} = useSearchResults()

  const categoryNameMapping = useMemo(() => {
    const mapping = new Map<string, Category>()
    for (const cat of [...categories.apps, ...categories.actions]) {
      mapping.set(cat.slug, cat)
    }
    return mapping
  }, [categories.actions, categories.apps])

  const headingText = useMemo(() => {
    if (query) {
      return `Search results for “${query}”`
    } else if (copilotApp) {
      return 'Copilot Extensions'
    } else if (category) {
      const categoryParam = category
      const cat = categoryParam ? categoryNameMapping.get(categoryParam) : undefined
      const listingType = type === 'actions' ? 'actions' : 'apps'
      return cat ? `${cat.name} ${listingType}` : 'Apps'
    } else if (type === 'actions') {
      return 'Actions'
    } else if (type === 'apps') {
      return 'Apps'
    }
    return 'Search results'
  }, [category, categoryNameMapping, copilotApp, query, type])

  const detailText = useMemo(() => {
    if (query) {
      return `${searchResults.total} ${searchResults.total === 1 ? 'result' : 'results'}`
    } else if (copilotApp) {
      return 'Extend Copilot capabilities using third party tools, services, and data'
    } else if (category) {
      const categoryParam = category
      const cat = categoryParam ? categoryNameMapping.get(categoryParam) : undefined
      return cat ? <SafeHTMLBox html={cat.description_html as SafeHTMLString} /> : ''
    } else if (type === 'actions') {
      return 'Automate your workflow from idea to production'
    } else if (type === 'apps') {
      return 'Build on your workflow with apps that integrate with GitHub'
    }
  }, [category, categoryNameMapping, copilotApp, query, searchResults.total, type])

  if (type === 'models') return <ModelsResultListHeader />

  return (
    <div className="d-flex flex-column flex-sm-row flex-justify-between flex-wrap gap-2">
      <div>
        <h2 className="f2 lh-condensed" {...testIdProps('heading-text')}>
          {headingText}
        </h2>
        {detailText && (
          <span className="fgColor-muted" {...testIdProps('detail-text')}>
            {detailText}
          </span>
        )}
      </div>
    </div>
  )
}
