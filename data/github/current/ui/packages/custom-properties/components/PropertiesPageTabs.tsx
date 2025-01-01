import type {PropertiesPageTabName} from '@github-ui/custom-properties-types'
import {human} from '@github-ui/formatters'
import {Link} from '@github-ui/react-core/link'
import {UnderlineNav} from '@primer/react'
import {useState} from 'react'
import {useSearchParams} from 'react-router-dom'

import {useListPropertiesPath} from '../hooks/use-properties-paths'
import styles from './PropertiesPageTabs.module.css'

interface Props {
  activeTab: PropertiesPageTabName
  definitionsCount: number
}

export function PropertiesPageTabs({definitionsCount, activeTab}: Props) {
  const [selectedTab, setSelectedTab] = useState<PropertiesPageTabName>(activeTab)
  const [params] = useSearchParams()
  const listPropertiesPath = useListPropertiesPath()

  function hrefBuilder(tab: PropertiesPageTabName): string {
    const newParams = new URLSearchParams(params)
    newParams.set('tab', tab)
    return `${listPropertiesPath}?${newParams.toString()}`
  }

  return (
    <UnderlineNav aria-label="Page selector" className={styles.PropertiesPageTabsNavigation}>
      <UnderlineNav.Item
        key="properties-tab"
        as={Link}
        to={hrefBuilder('properties')}
        {...(selectedTab === 'properties' && {'aria-current': true})}
        onSelect={() => setSelectedTab('properties')}
        counter={human(definitionsCount)}
      >
        <span>Properties</span>
      </UnderlineNav.Item>
      <UnderlineNav.Item
        key="set-values-tab"
        as={Link}
        to={hrefBuilder('set-values')}
        {...(selectedTab === 'set-values' && {'aria-current': true})}
        onSelect={() => setSelectedTab('set-values')}
      >
        <span>Set values</span>
      </UnderlineNav.Item>
    </UnderlineNav>
  )
}
