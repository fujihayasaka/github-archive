import safeStorage from '@github-ui/safe-storage'
import {ActionList, Button} from '@primer/react'
import {TabNav} from '@primer/react/deprecated'
import type React from 'react'
import {useCallback, useEffect, useState, type ReactNode} from 'react'
import {CopilotTab, type CopilotTabProps} from './CopilotTab'
import {CodespacesTabContent, CodespacesTabWrapper} from './CodespacesTab'
import {LocalTab, type LocalTabProps} from './LocalTab'
import {useCodeButtonData} from '../../pull-request-commits/page-data/loaders/use-code-button-data'
import {CodeMenuButton} from './CodeMenuButton'

const safeLocalStorage = safeStorage('localStorage')

export interface CodeDropdownButtonProps {
  primary: boolean
  size?: 'small' | 'large' | 'medium'
  showCodespacesTab?: boolean
  showCopilotTab?: boolean
  isEnterprise: boolean
  localTab?: ReactNode
  codespacesTab?: ReactNode
  copilotTab?: ReactNode
  localTabProps?: LocalTabProps
  codespacesPath?: string
  copilotTabProps?: CopilotTabProps
}

enum ActiveTab {
  Local = 'local',
  Codespaces = 'cloud',
  Copilot = 'copilot',
}

export function CodeDropdownButton(props: CodeDropdownButtonProps) {
  const {
    primary,
    size,
    showCodespacesTab,
    showCopilotTab,
    isEnterprise,
    localTab,
    codespacesTab,
    copilotTab,
    localTabProps,
    copilotTabProps,
    codespacesPath,
  } = props
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

  const onCopilotTabClick = useCallback((ev?: React.MouseEvent) => {
    setActiveTab(ActiveTab.Copilot)
    safeLocalStorage.setItem(localStorageDefaultTabKey, ActiveTab.Copilot)
    ev?.preventDefault()
  }, [])

  useEffect(() => {
    const defaultActiveTab = safeLocalStorage.getItem(localStorageDefaultTabKey)
    if (defaultActiveTab === ActiveTab.Codespaces && showCodespacesTab) {
      onCodespacesTabClick()
    }
    // Only run after the initial render.
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const tabLinkStyles = {
    height: '40px',
    width: '50%',
    borderBottomRightRadius: 0,
    borderBottomLeftRadius: 0,
    borderTop: 0,
    color: 'fg.muted',
    '&.selected:hover': {
      backgroundColor: 'unset',
      borderColor: 'border.default',
      borderBottom: 0,
    },
  }

  const showTabNav = !isEnterprise && (showCodespacesTab || showCopilotTab)

  return (
    <CodeMenuButton size={size} isPrimary={primary}>
      {showTabNav && (
        <TabNav>
          <TabNav.Link
            as={Button}
            selected={activeTab === ActiveTab.Local}
            onClick={onLocalTabClick}
            sx={{
              ...tabLinkStyles,
              borderLeft: 0,
            }}
          >
            Local
          </TabNav.Link>
          {!isEnterprise && showCodespacesTab && (
            <TabNav.Link
              as={Button}
              selected={activeTab === ActiveTab.Codespaces}
              onClick={onCodespacesTabClick}
              sx={{
                ...tabLinkStyles,
                borderRight: showCopilotTab ? null : 0,
              }}
            >
              Codespaces
            </TabNav.Link>
          )}
          {showCopilotTab && (
            <TabNav.Link
              as={Button}
              selected={activeTab === ActiveTab.Copilot}
              onClick={onCopilotTabClick}
              sx={{
                ...tabLinkStyles,
                borderRight: 0,
              }}
            >
              Copilot
            </TabNav.Link>
          )}
        </TabNav>
      )}
      <ActionList className="react-overview-code-button-action-list py-0">
        {activeTab === ActiveTab.Local && (localTab || renderLocalTab(localTabProps))}
        {activeTab === ActiveTab.Codespaces && (codespacesTab || renderCodespacesTab(codespacesPath))}
        {activeTab === ActiveTab.Copilot && (copilotTab || renderCopilotTab(copilotTabProps))}
      </ActionList>
    </CodeMenuButton>
  )
}

function renderLocalTab(localTabProps?: LocalTabProps) {
  if (!localTabProps) return null

  return <LocalTab {...localTabProps} />
}

function renderCopilotTab(copilotTabProps?: CopilotTabProps) {
  if (!copilotTabProps) return null

  return <CopilotTab {...copilotTabProps} />
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
