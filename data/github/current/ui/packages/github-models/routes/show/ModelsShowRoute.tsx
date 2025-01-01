import {ModelLayout, type ModelLayoutTab} from './components/ModelLayout'
import {Evaluation} from './components/Evaluation'
import {Readme} from './components/Readme'
import {License} from './components/License'
import {Transparency} from './components/Transparency'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {GettingStartedPayload} from '../../types'
import {useSearchParams} from 'react-router-dom'
import {normalizeModelPublisher} from '../../utils/normalize-model-strings'
import {replaceNavigationBreadcrumbs} from '@github-ui/global-navigation'
import {useEffect} from 'react'
import {modelsCatalogPath} from '@github-ui/paths'

const defaultTab = 'readme'

const renderTab = (tab: string) => {
  switch (tab) {
    case 'evaluation':
      return <Evaluation />
    case 'license':
      return <License />
    case 'transparency':
      return <Transparency />
    default:
      return <Readme />
  }
}

export function ModelsShowRoute() {
  const [searchParams] = useSearchParams()
  const activeTab = (searchParams.get('tab') || defaultTab) as ModelLayoutTab
  const {model, modelInputSchema, gettingStarted, isLoggedIn} = useRoutePayload<GettingStartedPayload>()

  // Update global navigation breadcrumbs for this route
  useEffect(() => {
    if (isLoggedIn) {
      const breadcrumbs = [
        {label: 'Marketplace', href: '/marketplace'},
        {label: 'Models', href: modelsCatalogPath()},
        {label: normalizeModelPublisher(model.publisher)},
      ]

      replaceNavigationBreadcrumbs(breadcrumbs)
    }
  }, [model, isLoggedIn])

  return (
    <ModelLayout
      activeTab={activeTab}
      model={model}
      modelInputSchema={modelInputSchema}
      gettingStarted={gettingStarted}
    >
      {renderTab(activeTab)}
    </ModelLayout>
  )
}
