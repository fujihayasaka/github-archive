import {Button, Spinner} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useState, type PropsWithChildren, useEffect} from 'react'
import {ShortcutsGroupList} from './ShortcutsGroupList'
import strings from '../strings'
import type {ShortcutsGroup} from '../types'
import {getAllRegisteredCommands, type UICommandGroup} from '@github-ui/ui-commands/internal'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {normalizeSequence} from '@github-ui/hotkey'

import styles from './ShortcutsDialog.module.css'

type APIShortcuts = {
  commands: {
    global: UICommandGroup
    [key: string]: UICommandGroup
  }
}
interface ShortcutsDialogProps {
  visible: boolean
  onVisibleChange: (visible: boolean) => void
  docsUrl: string
}

const LoadingState = () => (
  <div role="status" className={styles.LoadingStateContainer}>
    <Spinner size="large" />
    <span className="sr-only">{strings.loading}</span>
  </div>
)

const parseShortcut = (keybinding?: string | string[], alwaysCtrl?: boolean) => {
  if (Array.isArray(keybinding)) {
    return alwaysCtrl
      ? keybinding.map(kb => normalizeSequence(kb))
      : keybinding.map(kb => normalizeSequence(kb.replace(/ctrl/, 'Mod+')))
  }
  return alwaysCtrl ? normalizeSequence(keybinding ?? '') : normalizeSequence(keybinding?.replace(/ctrl/, 'Mod+') ?? '')
}

const Columns = ({children}: PropsWithChildren) => <div className={styles.ColumnsContainer}>{children}</div>

const Column = ({children}: PropsWithChildren) => <div className={styles.Column}>{children}</div>

export const ShortcutsDialog = ({visible, onVisibleChange, docsUrl}: ShortcutsDialogProps) => {
  const [siteWideShortcuts, setSiteWideShortcuts] = useState<ShortcutsGroup>({
    service: {id: 'global', name: 'Global'},
    commands: [],
  })
  const [shortcutGroups, setShortcutGroups] = useState<ShortcutsGroup[]>([])
  const [isLoading, setIsLoading] = useState(false)

  // Fetch keyboard shortcuts from the server
  useEffect(() => {
    // Skip the global service since those commands are core web keybindings that don't need to be documented
    const uiCommandGroups = getAllRegisteredCommands().filter(group => group.service.id !== 'github')

    const fetchShortcuts = async () => {
      setIsLoading(true)
      const metaKeyboardShortcuts = document.querySelector<HTMLMetaElement>('meta[name=github-keyboard-shortcuts]')
      if (!metaKeyboardShortcuts) throw new Error('The "github-keyboard-shortcuts" meta tag must be present')
      // The multi-word contexts are separated with hyphens, but their corresponding objects in
      // `keyboard_shortcuts_helper.rb` use underscores instead. Manually convert here so our API endpoint correctly
      // finds all relevant contexts.
      const options = {contexts: metaKeyboardShortcuts.content.replace(/-/g, '_')}
      const url = `/site/keyboard_shortcuts?${new URLSearchParams(options).toString()}`
      const resp = await verifiedFetchJSON(url, {method: 'GET'})
      if (resp.ok) {
        const shortcuts: APIShortcuts = await resp.json()
        const {global, ...rest} = shortcuts.commands
        setSiteWideShortcuts({
          service: {
            id: 'global',
            name: strings.siteWideShortcuts,
          },
          commands: [
            ...global.commands,
            ...(uiCommandGroups.find(uiCommandGroup => uiCommandGroup.service.id === 'global')?.commands ?? []),
          ].map(command => {
            return {
              ...command,
              keybinding: parseShortcut(command.keybinding, command.alwaysCtrl),
            }
          }),
        })

        const transformedGroups = [...Object.values(rest), ...uiCommandGroups].map(group => {
          return {
            ...group,
            commands: group.commands.map(command => {
              return {
                ...command,
                keybinding: parseShortcut(command.keybinding, command.alwaysCtrl),
              }
            }),
          }
        })

        setShortcutGroups(transformedGroups)
      } else {
        setShortcutGroups(
          uiCommandGroups.map(group => {
            return {
              ...group,
              commands: group.commands.map(command => {
                return {
                  ...command,
                  keybinding: parseShortcut(command.keybinding, command.alwaysCtrl),
                }
              }),
            }
          }),
        )
      }
      setIsLoading(false)
    }

    if (visible) fetchShortcuts()
  }, [visible])

  if (!visible) return null
  return (
    <Dialog
      title={strings.keyboardShortcuts}
      aria-modal="true"
      width="xlarge"
      height="large"
      onClose={() => onVisibleChange(false)}
      className={styles.ShortcutsDialogRoot}
    >
      {isLoading ? (
        <LoadingState />
      ) : (
        <Columns>
          <Column>
            {shortcutGroups.map(group => (
              <ShortcutsGroupList group={group} key={group.service.id} />
            ))}
          </Column>

          <Column>
            <ShortcutsGroupList group={siteWideShortcuts} key={siteWideShortcuts.service.id} />
            <Button as="a" href={docsUrl} className={styles.FullWidthButton}>
              View all keyboard shortcuts
            </Button>
          </Column>
        </Columns>
      )}
    </Dialog>
  )
}
