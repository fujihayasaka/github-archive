import {PrimerFeatureFlags} from '@github-ui/react-core/PrimerFeatureFlags'
import {getQueryClient} from '@github-ui/react-core/query-client'
import useColorModes from '@github-ui/react-core/use-color-modes'
import {XIcon} from '@primer/octicons-react'
import {memo, Suspense, useCallback, useEffect, useMemo, type PropsWithChildren} from 'react'
import styles from './StaffBarReactQueryDevToolsPanel.module.css'
// eslint-disable-next-line no-restricted-imports
import {IconButton, ThemeProvider} from '@primer/react'
import {AsyncReactQueryDevtoolsPanel} from './AsyncReactQueryDevtoolsPanel'
import {setIsQueryPanelOpen, setSessionHeight, setSessionWidth} from './session-store'
import {useDevToolsOpenState} from './use-devtools-open-state'
import {useSessionSizes} from './use-session-values'

const MESSAGES = {
  Close: 'Close tanstack react query devtools panel',
  Open: 'Open tanstack react query devtools panel',
}

export function Devtools({
  toggleDevtoolsVisibilityButton,
  handleDevtoolsVisibilityChange,
}: {
  toggleDevtoolsVisibilityButton: HTMLButtonElement
  handleDevtoolsVisibilityChange: (next?: boolean) => void
}) {
  const {colorMode, dayScheme, nightScheme} = useColorModes()
  const isOpen = useDevToolsOpenState()
  /**
   * Sync staffbar toggle tooltip and aria-label based on state
   */
  useEffect(() => {
    if (isOpen) {
      toggleDevtoolsVisibilityButton.classList.remove('color-fg-on-emphasis')
      toggleDevtoolsVisibilityButton.setAttribute('aria-pressed', 'true')
      toggleDevtoolsVisibilityButton.classList.add('color-text-white')
    } else {
      toggleDevtoolsVisibilityButton.classList.remove('color-text-white')
      toggleDevtoolsVisibilityButton.setAttribute('aria-pressed', 'false')
      toggleDevtoolsVisibilityButton.classList.add('color-fg-on-emphasis')
    }

    const text = isOpen ? MESSAGES.Close : MESSAGES.Open
    toggleDevtoolsVisibilityButton.setAttribute('aria-label', text)
    const tooltip = document.querySelector(`tool-tip[for="${toggleDevtoolsVisibilityButton.id}"]`)
    if (tooltip) {
      tooltip.textContent = text
    }
  }, [isOpen, toggleDevtoolsVisibilityButton])

  if (!isOpen) return null
  return (
    <Suspense fallback={null}>
      <PrimerFeatureFlags>
        <ThemeProvider colorMode={colorMode} dayScheme={dayScheme} nightScheme={nightScheme} preventSSRMismatch>
          <ResizableDevtools handleDevtoolsVisibilityChange={handleDevtoolsVisibilityChange} />
        </ThemeProvider>
      </PrimerFeatureFlags>
    </Suspense>
  )
}

function createMouseDownHandler(onMouseMove: (e: MouseEvent) => void) {
  return (ev: React.MouseEvent) => {
    // prevent background text from being highlighted when dragging starts
    ev.preventDefault()
    ev.stopPropagation()

    const onMouseUp = () => {
      window.removeEventListener('mousemove', onMouseMove)
      window.removeEventListener('mouseup', onMouseUp)
    }

    window.addEventListener('mousemove', onMouseMove)
    window.addEventListener('mouseup', onMouseUp)
  }
}

function ResizableDevtools({
  handleDevtoolsVisibilityChange,
}: {
  handleDevtoolsVisibilityChange: (next?: boolean) => void
}) {
  const {height, width, maxWidth, maxHeight, minHeight, minWidth} = useSessionSizes()

  return (
    <ResizableContainer height={height} width={width}>
      <HeightExpansionDraggableBar minHeight={minHeight} height={height} maxHeight={maxHeight} />
      <WidthExpansionDraggableBar minWidth={minWidth} width={width} maxWidth={maxWidth} />
      <CloseButton />

      <DevPanel handleDevtoolsVisibilityChange={handleDevtoolsVisibilityChange} />
    </ResizableContainer>
  )
}

const DevPanel = memo(function DevPanel({
  handleDevtoolsVisibilityChange,
}: {
  handleDevtoolsVisibilityChange: (next?: boolean) => void
}) {
  return (
    <AsyncReactQueryDevtoolsPanel
      style={{
        width: '100%',
        height: '100%',
      }}
      client={getQueryClient()}
      onClose={() => {
        handleDevtoolsVisibilityChange(false)
      }}
    />
  )
})

const CloseButton = memo(function CloseButton() {
  return (
    <IconButton
      icon={XIcon}
      aria-label={MESSAGES.Close}
      onClick={() => setIsQueryPanelOpen(false)}
      size="small"
      variant="default"
      className={styles.closeButton}
    />
  )
})

const ResizableContainer = memo(function ResizableContainer({
  height,
  width,
  children,
}: PropsWithChildren<{height: number; width: number}>) {
  return (
    <div
      className={styles.container}
      style={{
        width: `${width}px`,
        height: `${height}px`,
      }}
    >
      {children}
    </div>
  )
})

const HeightExpansionDraggableBar = memo(function HeightExpansionDraggableBar({
  height,
  maxHeight,
  minHeight,
}: {
  height: number
  minHeight: number
  maxHeight: number
}) {
  const onMouseDown = useMemo(
    () =>
      createMouseDownHandler((e: MouseEvent) => {
        const newHeight = Math.max(minHeight, Math.min(maxHeight || 0, window.innerHeight - e.clientY))
        setSessionHeight(newHeight)
      }),
    [maxHeight, minHeight],
  )

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.key === 'ArrowUp') {
        e.preventDefault()
        e.stopPropagation()
        setSessionHeight(prev => Math.min(prev + 10, maxHeight || 0))
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      } else if (e.key === 'ArrowDown') {
        e.preventDefault()
        e.stopPropagation()
        setSessionHeight(prev => Math.max(prev - 10, minHeight))
      }
    },
    [maxHeight, minHeight],
  )

  return (
    /* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */
    <div
      role="separator"
      aria-orientation="horizontal"
      aria-label="Resize devtools panel height"
      aria-valuemin={minHeight}
      aria-valuenow={height}
      aria-valuemax={maxHeight}
      // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
      tabIndex={0}
      onKeyDown={onKeyDown}
      onMouseDown={onMouseDown}
      className={styles.topDragBar}
    />
  )
})
const WidthExpansionDraggableBar = memo(function WidthExpansionDraggableBar({
  width,
  minWidth,
  maxWidth,
}: {
  width: number
  maxWidth: number
  minWidth: number
}) {
  const handleVerticalMouseDown = useMemo(
    () =>
      createMouseDownHandler((e: MouseEvent) => {
        const newWidth = Math.max(minWidth, Math.min(maxWidth || 0, e.clientX))
        setSessionWidth(newWidth)
      }),
    [maxWidth, minWidth],
  )

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.key === 'ArrowRight') {
        e.preventDefault()
        e.stopPropagation()
        setSessionWidth(prev => Math.min(prev + 10, maxWidth))
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault()
        e.stopPropagation()
        setSessionWidth(prev => Math.max(prev - 10, minWidth))
      }
    },
    [maxWidth, minWidth],
  )

  return (
    /* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize devtools panel width"
      aria-valuemin={minWidth}
      aria-valuenow={width}
      aria-valuemax={maxWidth}
      // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
      tabIndex={0}
      onKeyDown={onKeyDown}
      onMouseDown={handleVerticalMouseDown}
      className={styles.rightDragBar}
    />
  )
})
