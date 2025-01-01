import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {
  AiModelIcon,
  DatabaseIcon,
  GoalIcon,
  ImageIcon,
  LogIcon,
  PaintbrushIcon,
  SparkleFillIcon,
} from '@primer/octicons-react'
import {clsx} from 'clsx'
import {useEffect, useRef} from 'react'

import {useTargetedEditsContext} from '../../contexts/TargetedEditsContext'
import {useWorkbenchUI} from '../../contexts/WorkbenchUIContext'
import type {UseWorkbenchReturn} from '../../hooks/use-workbench'
import {Panel, type Panel as PanelType} from '../../types/workbench-types'
import {PanelBlankslate} from './PanelBlankslate'
import {AiPanel} from './panels/AiPanel'
import {AssetsPanel} from './panels/AssetsPanel'
import {DataPanel} from './panels/DataPanel'
import IteratePanel from './panels/IteratePanel'
import {TargetedEditsPanel} from './panels/TargetedEditsPanel'
import {ThemePanel} from './panels/ThemePanel'
import styles from './SidePanel.module.css'

const PANELS = [
  {type: Panel.ITERATE, label: 'Iterate', icon: SparkleFillIcon},
  {type: Panel.THEME, label: 'Theme', icon: PaintbrushIcon},
  {type: Panel.DATA, label: 'Data', icon: DatabaseIcon},
  {type: Panel.AI, label: 'AI', icon: AiModelIcon},
  {type: Panel.ASSETS, label: 'Assets', icon: ImageIcon},
  {type: Panel.LOGS, label: 'Logs', icon: LogIcon},
] as const

interface SidePanelProps {
  workbenchData: UseWorkbenchReturn
  selectedPanel: PanelType
  setSelectedPanel: (panel: PanelType) => void
}

export function SidePanel({workbenchData, selectedPanel, setSelectedPanel}: SidePanelProps) {
  const {sidePanelOpen} = useWorkbenchUI()
  const {selectedElement, targetedEditsEnabled, disableTargetedEdits} = useTargetedEditsContext()
  const containerRef = useRef<HTMLDivElement>(null)

  // Set tabindex on all interactive elements when the panel is collapsed/expanded
  useEffect(() => {
    if (!containerRef.current) return

    const focusableElements = containerRef.current.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
    )

    for (const element of focusableElements) {
      if (element instanceof HTMLElement) {
        // Skip the toggle button so it can always be focused
        if (element.classList.contains(styles.toggleButton)) continue
        element.tabIndex = sidePanelOpen ? 0 : -1
      }
    }
  }, [sidePanelOpen])

  useEffect(() => {
    if (targetedEditsEnabled) {
      setSelectedPanel('theme')
    }
  }, [targetedEditsEnabled, setSelectedPanel])

  return (
    <div className={styles.container} ref={containerRef}>
      {/* Horizontal navigation bar */}
      <div className={styles.navContainer}>
        <div className={styles.navList}>
          {PANELS.map(panel => {
            if (copilotFeatureFlags.workbenchIteratePanel && panel.type === 'logs') {
              return null
            }
            return (
              <button
                type="button"
                key={panel.type}
                className={clsx(styles.navButton, {
                  [styles.navButtonActive]: selectedPanel === panel.type,
                })}
                onClick={() => {
                  setSelectedPanel(panel.type)
                  if (panel.type === 'theme' && targetedEditsEnabled) {
                    disableTargetedEdits() // Reset targeted edits when switching to theme panel
                  }
                }}
              >
                <span className={styles.navButtonLabel}>{panel.label}</span>
              </button>
            )
          })}
        </div>
      </div>

      {/* Panel content area */}
      <div className={styles.panel}>
        {selectedPanel === 'iterate' && <IteratePanel workbenchData={workbenchData} />}
        {selectedPanel === 'theme' &&
          (targetedEditsEnabled ? (
            selectedElement ? (
              <TargetedEditsPanel
                key={JSON.stringify(selectedElement.location?.start ?? selectedElement.component.location?.start)}
                element={selectedElement}
                onClose={() => {
                  disableTargetedEdits()
                  setSelectedPanel('theme')
                }}
              />
            ) : (
              <PanelBlankslate title="Select an element to edit" icon={GoalIcon} />
            )
          ) : (
            <ThemePanel />
          ))}
        {selectedPanel === 'data' && <DataPanel />}
        {selectedPanel === 'ai' && (
          <AiPanel isFetching={workbenchData.isFetching} workbenchId={workbenchData.workbench.id} />
        )}
        {selectedPanel === 'assets' && <AssetsPanel />}
      </div>
    </div>
  )
}
