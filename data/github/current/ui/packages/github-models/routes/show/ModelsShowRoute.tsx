import {useSearchParams} from '@github-ui/use-navigate'
import type React from 'react'
import {useState} from 'react'
import {ModelLayout, type ModelLayoutTab} from '../playground/components/GettingStartedDialog/ModelLayout'
import {Evaluation} from './components/Evaluation'
import {Readme} from './components/Readme'
import {License} from './components/License'
import {Transparency} from './components/Transparency'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {GettingStartedPayload} from '../../types'

export function ModelsShowRoute() {
  const [searchParams] = useSearchParams()
  const selectedTabFromUrl = (searchParams.get('tab') || 'readme') as ModelLayoutTab
  const [selectedTab, setSelectedTab] = useState<ModelLayoutTab>(selectedTabFromUrl)
  const {model, modelInputSchema, gettingStarted} = useRoutePayload<GettingStartedPayload>()

  const selectTab = (
    tab: ModelLayoutTab,
    e: React.KeyboardEvent<HTMLAnchorElement> | React.MouseEvent<HTMLAnchorElement>,
  ) => {
    const url = new URL('', window.location.href)
    url.searchParams.set('tab', tab)
    history.pushState(null, '', url)
    setSelectedTab(tab)
    e.preventDefault()
  }

  const renderTab = (tab: ModelLayoutTab): JSX.Element => {
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

  return (
    <ModelLayout
      activeTab={selectedTab}
      selectTab={selectTab}
      model={model}
      modelInputSchema={modelInputSchema}
      gettingStarted={gettingStarted}
    >
      {renderTab(selectedTab)}
    </ModelLayout>
  )
}
