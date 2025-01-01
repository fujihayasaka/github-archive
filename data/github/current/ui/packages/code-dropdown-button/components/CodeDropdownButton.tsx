import safeStorage from '@github-ui/safe-storage'
import {Button} from '@primer/react'
import {TabNav} from '@primer/react/deprecated'
import type React from 'react'
import {useCallback, useEffect, useState, type ReactNode} from 'react'
import {CodespacesTabContent, CodespacesTabWrapper} from './CodespacesTab'
import {LocalTab, type LocalTabProps} from './LocalTab'

import {useCodeButtonData} from '@github-ui/pull-requests/page-data/loaders/use-code-button-data'
import {CodeMenuButton} from './CodeMenuButton'
import styles from './CodeDropdownButton.module.css'

const safeLocalStorage = safeStorage('localStorage')

export interface CodeDropdownButtonProps {
  primary: boolean
  size?: 'small' | 'large' | 'medium'
  showCodespacesTab?: boolean
  isEnterprise: boolean
  localTab?: ReactNode
  codespacesTab?: ReactNode
  localTabProps?: LocalTabProps
  codespacesPath?: string
}

const ActiveTab = {
  Local: 'local',
  Codespaces: 'cloud',
  Copilot: 'copilot',
} as const

type ActiveTab = (typeof ActiveTab)[keyof typeof ActiveTab]

export function CodeDropdownButton(props: CodeDropdownButtonProps) {
  const {primary, size, showCodespacesTab, isEnterprise, localTab, codespacesTab, localTabProps, codespacesPath} = props
  const localStorageDefaultTabKey = 'code-button-default-tab'
  const [activeTab, setActiveTab] = useState<string>(ActiveTab.Local)

  const onCodespacesTabClick = useCallback((ev?: React.MouseEvent) => {
    setActiveTab(ActiveTab.Codespaces)
    safeLocalStorage.setItem(localStorageDefaultTabKey, ActiveTab.Codespaces)
    ev?.preventDefault()
  }, [])

  const onLocalTabClick = useCallback((ev?: React.MouseEvent) => {
    setActiveTab(ActiveTab.Local)
    safeLocalStorage.setItem(localStorageDefaultTabKey, ActiveTab.Local)
    ev?.preventDefault()
  }, [])

  useEffect(() => {
    const defaultActiveTab = safeLocalStorage.getItem(localStorageDefaultTabKey)
    if (defaultActiveTab === ActiveTab.Codespaces && showCodespacesTab) {
      onCodespacesTabClick()
    }
    // Only run after the initial render.
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const showTabNav = !isEnterprise && showCodespacesTab

  return (
    <CodeMenuButton size={size} isPrimary={primary}>
      {showTabNav && (
        <TabNav className={styles.TabNav}>
          <TabNav.Link
            as={Button}
            selected={activeTab === ActiveTab.Local}
            onClick={onLocalTabClick}
            className={styles.NavItem}
          >
            Local
          </TabNav.Link>
          {!isEnterprise && showCodespacesTab && (
            <TabNav.Link
              as={Button}
              selected={activeTab === ActiveTab.Codespaces}
              onClick={onCodespacesTabClick}
              className={styles.NavItem}
            >
              Codespaces
            </TabNav.Link>
          )}
        </TabNav>
      )}
      <div className="react-overview-code-button-action-list py-0">
        {activeTab === ActiveTab.Local && (localTab || renderLocalTab(localTabProps))}
        {activeTab === ActiveTab.Codespaces && (codespacesTab || renderCodespacesTab(codespacesPath))}
      </div>
    </CodeMenuButton>
  )
}

function renderLocalTab(localTabProps?: LocalTabProps) {
  if (!localTabProps) return null

  return <LocalTab {...localTabProps} />
}

function renderCodespacesTab(codespacesPath?: string) {
  if (!codespacesPath) return null

  return (
    <CodespacesTabWrapper>
      <SuspendedCodespacesTab codespacesPath={codespacesPath} />
    </CodespacesTabWrapper>
  )
}

function SuspendedCodespacesTab(props: {codespacesPath: string}) {
  const data = useCodeButtonData().data
  return <CodespacesTabContent codespacesPath={props.codespacesPath} {...data} />
}
