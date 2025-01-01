import {ModelLayout, type ModelLayoutTab} from './components/ModelLayout'
import {Evaluation} from './components/Evaluation'
import {Readme} from './components/Readme'
import {License} from './components/License'
import {Transparency} from './components/Transparency'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {GettingStartedPayload} from '../../types'
import {useSearchParams} from 'react-router-dom'

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
  const {model, modelInputSchema, gettingStarted} = useRoutePayload<GettingStartedPayload>()

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
