import {
  ChevronDownIcon,
  DotFillIcon,
  HistoryIcon,
  LightBulbIcon,
  PaperAirplaneIcon,
  PaperclipIcon,
  ScreenNormalIcon,
  SparkleFillIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Spinner, TextInput} from '@primer/react'
import {useCallback, useEffect, useRef, useState} from 'react'

import type {Step} from '../utilities/generate-iteration'
import styles from './IterateModal.module.css'

interface IterationModalProps {
  closeModal: () => void
  submitPrompt: (prompt: string, step: Step) => Promise<void>
  previousRefinements: string[]
  isFetching: boolean
  suggestions: string[]
  step: Step
}

const colors = [
  {label: 'Blue', value: 'var(--fgColor-accent)'},
  {label: 'Green', value: 'var(--fgColor-open)'},
  {label: 'Orange', value: 'var(--fgColor-attention)'},
  {label: 'Red', value: 'var(--fgColor-closed)'},
  {label: 'Purple', value: 'var(--fgColor-done)'},
  {label: 'Pink', value: 'var(--fgColor-sponsors)'},
  {label: 'Black', value: 'var(--fgColor-black)'},
  {label: 'White', value: 'var(--fgColor-default)'},
]

export function IterateModal({
  closeModal,
  submitPrompt,
  previousRefinements,
  isFetching,
  suggestions,
  step,
}: IterationModalProps) {
  const [tab, setTab] = useState(0)
  const [selectedHistoryItem, setSelectedHistoryItem] = useState(previousRefinements.length - 1)
  const [inputValue, setInputValue] = useState<string>('')

  const actionListRef = useRef<HTMLDivElement>(null)

  const [accent, setAccent] = useState({label: 'Blue', value: 'var(--fgColor-accent)'})
  const [accentSecondary, setAccentSecondary] = useState({label: 'Green', value: 'var(--fgColor-open)'})

  // When previousRefinements changes, update selectedHistoryItem to point to the latest item
  useEffect(() => {
    setSelectedHistoryItem(previousRefinements.length - 1)
  }, [previousRefinements.length, selectedHistoryItem])

  const scrollToBottom = ({smooth}: {smooth: boolean}) => {
    if (!actionListRef.current) return
    if (smooth)
      actionListRef.current.scrollTo({
        top: actionListRef.current.scrollHeight,
        behavior: 'smooth',
      })
    else actionListRef.current.scrollTop = actionListRef.current.scrollHeight
  }

  /** Instant scroll to bottom when history tab is selected */
  useEffect(() => {
    if (tab === 2) scrollToBottom({smooth: false})
  }, [tab])

  /** Smooth scroll to bottom when a prompt is entered */
  useEffect(() => {
    scrollToBottom({smooth: true})
  }, [previousRefinements])

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.key !== 'Enter' || e.shiftKey) return

      e.preventDefault()
      submitPrompt(inputValue, step)
      setInputValue('')
    },
    [inputValue, submitPrompt, step],
  )

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        {/* header center */}
        <div className={styles.tabs}>
          {tab === 0 ? (
            <div className={styles.title}>
              <SparkleFillIcon />
              <span className="text-bold">Iterate</span>
            </div>
          ) : (
            <IconButton aria-label="Iterate" icon={SparkleFillIcon} variant="invisible" onClick={() => setTab(0)} />
          )}

          {tab === 1 ? (
            <div className={styles.title}>
              <ScreenNormalIcon />
              <span className="text-bold">Edit</span>
            </div>
          ) : (
            <IconButton aria-label="Edit" icon={ScreenNormalIcon} variant="invisible" onClick={() => setTab(1)} />
          )}

          {tab === 2 ? (
            <div className={styles.title}>
              <HistoryIcon />
              <span className="text-bold">History</span>
            </div>
          ) : (
            <IconButton aria-label="History" icon={HistoryIcon} variant="invisible" onClick={() => setTab(2)} />
          )}
        </div>

        {/* header end */}
        <IconButton
          aria-label="Close iteration panel"
          icon={ChevronDownIcon}
          variant="invisible"
          onClick={closeModal}
        />
      </div>

      <div ref={actionListRef} className={styles.actionList}>
        <ActionList>
          {tab === 0 && (
            <>
              {suggestions.map(text => (
                <ActionList.LinkItem onClick={() => submitPrompt(text, step)} key={`workbench-iterate-modal-${text}`}>
                  <ActionList.LeadingVisual>
                    <LightBulbIcon className={styles.lightBulb} />
                  </ActionList.LeadingVisual>
                  {text}
                </ActionList.LinkItem>
              ))}
            </>
          )}

          {tab === 1 && (
            <div className={styles.grid}>
              <span className={styles.firstInRow}>Margin</span>
              <TextInput />
              <TextInput className={styles.lastInRow} />

              <span className={styles.firstInRow}>Padding</span>
              <TextInput />
              <TextInput className={styles.lastInRow} />

              <div className={styles.gridDivider} />

              <span className={styles.firstInRow}>Accent</span>
              <div className={`${styles.actionMenuContainer} ${styles.lastInRow}`}>
                <ActionMenu>
                  <ActionMenu.Button
                    block
                    alignContent="start"
                    leadingVisual={
                      <div style={{fill: accent.value}}>
                        <DotFillIcon size={32} className={styles.circleInherit} />
                      </div>
                    }
                  >
                    {accent.label}
                  </ActionMenu.Button>
                  <ActionMenu.Overlay align="start">
                    <ActionList selectionVariant="single">
                      {colors.map(e => (
                        <ActionList.Item
                          key={`accent-${JSON.stringify(e)}`}
                          selected={e.label === accentSecondary.label}
                          onSelect={() => setAccent(e)}
                        >
                          <ActionList.LeadingVisual>
                            <div style={{fill: e.value}}>
                              <DotFillIcon size={32} className={styles.circleInherit} />
                            </div>
                          </ActionList.LeadingVisual>
                          {e.label}
                        </ActionList.Item>
                      ))}
                    </ActionList>
                  </ActionMenu.Overlay>
                </ActionMenu>
              </div>

              <span className={styles.firstInRow}>Secondary accent</span>
              <div className={`${styles.actionMenuContainer} ${styles.lastInRow}`}>
                <ActionMenu>
                  <ActionMenu.Button
                    block
                    alignContent="start"
                    leadingVisual={
                      <div style={{fill: accentSecondary.value}}>
                        <DotFillIcon size={32} className={styles.circleInherit} />
                      </div>
                    }
                  >
                    {accentSecondary.label}
                  </ActionMenu.Button>
                  <ActionMenu.Overlay align="start">
                    <ActionList selectionVariant="single">
                      {colors.map(e => (
                        <ActionList.Item
                          key={`accent-${JSON.stringify(e)}`}
                          selected={e.label === accentSecondary.label}
                          onSelect={() => setAccentSecondary(e)}
                        >
                          <ActionList.LeadingVisual>
                            <div style={{fill: e.value}}>
                              <DotFillIcon size={32} className={styles.circleInherit} />
                            </div>
                          </ActionList.LeadingVisual>
                          {e.label}
                        </ActionList.Item>
                      ))}
                    </ActionList>
                  </ActionMenu.Overlay>
                </ActionMenu>
              </div>

              <div className={styles.gridDivider} />

              <span className={styles.firstInRow}>TBD</span>
              <TextInput className={`${styles.longInput} ${styles.lastInRow}`} />
            </div>
          )}

          {tab === 2 && (
            <>
              {previousRefinements.map((text, i) => (
                <ActionList.LinkItem onClick={() => setSelectedHistoryItem(i)} key={`workbench-iterate-modal-${text}`}>
                  <ActionList.LeadingVisual>
                    <DotFillIcon className={i === selectedHistoryItem ? styles.actionListItemSelected : ''} />
                  </ActionList.LeadingVisual>
                  {text}
                </ActionList.LinkItem>
              ))}
            </>
          )}
        </ActionList>
      </div>

      <form className={styles.form}>
        <textarea
          autoFocus
          id="iterate-modal-input"
          className={styles.textarea}
          rows={1}
          placeholder="Refine your spark…"
          value={inputValue}
          onChange={e => setInputValue(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={isFetching}
          aria-disabled={isFetching}
        />
        <div className={styles.inputActions}>
          {isFetching && <Spinner size="small" className={styles.spinner} />}
          <IconButton aria-label="Add attachment" icon={PaperclipIcon} variant="invisible" onClick={() => {}} />
          <IconButton
            aria-label="Send now"
            icon={PaperAirplaneIcon}
            variant="invisible"
            onClick={() => {
              submitPrompt(inputValue, step)
              setInputValue('')
            }}
          />
        </div>
      </form>
    </div>
  )
}
