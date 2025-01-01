import {isMacOS} from '@github-ui/get-os'
import {testIdProps} from '@github-ui/test-id-props'
import {useIgnoreKeyboardActionsWhileComposing} from '@github-ui/use-ignore-keyboard-actions-while-composing'
import {type Icon, IssueDraftIcon, IssueOpenedIcon, RepoIcon} from '@primer/octicons-react'
import {ActionList, type BetterSystemStyleObject, Box, Text, useRefObjectAsForwardedRef} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {KeybindingHint} from '@primer/react/experimental'
import {forwardRef, Fragment, useCallback, useEffect, useId, useMemo, useRef, useSyncExternalStore} from 'react'

import {OmnibarDiscoverSuggestionsUI} from '../api/stats/contracts'
import {getEnabledFeatures} from '../helpers/feature-flags'
import {isIssueOrPullRequestUrl} from '../helpers/item-url'
import {type GetItemPropsAdditionalHandlers, useAutocomplete} from '../hooks/common/use-autocomplete'
import {useControlledRef} from '../hooks/common/use-controlled-ref'
import {useSidePanel} from '../hooks/use-side-panel'
import {FocusType, NavigationDirection} from '../navigation/types'
import {Resources} from '../strings'
import {PickerItem, PickerList, useAdjustPickerPosition} from './common/picker-list'
import {Portal} from './common/portal'
import {useStartIssueCreator} from './issue-creator'
import {OmnibarPlaceholder} from './omnibar/omnibar-placeholder'
import type {OmnibarItemAttrs, OmnibarMenu} from './omnibar/types'
import {BaseCell} from './react_table/cells/base-cell'
import {moveTableFocus, useStableTableNavigation} from './react_table/navigation'
import type {RenderInput} from './suggested-item-picker'

type DiscoveryInputProps = {
  inputRef: React.RefObject<HTMLInputElement>
  // This is a render prop that we invoke to render the textbox in the omnibar
  // This allows the components to hook into keyboard events
  renderInput: RenderInput
  newItemAttributes?: OmnibarItemAttrs
  omnibarText: string
  setOmnibarText: (value: string) => void
  /** The default placeholder to show when the omnibar does not have focus */
  defaultPlaceholder: React.ReactNode
  /** Whether the input is disabled*/
  isDisabled?: boolean
  createDraft: (item: string, options?: Partial<{shouldFocusInput?: boolean}>) => Promise<void>
  isFocused?: boolean
  omnibarMenu: OmnibarMenu
  setOmnibarMenu: (value: OmnibarMenu) => void
}

type DiscoveryMenuItem = {
  icon: Icon
  title: string
  shortcut?: string
  action: string
  shortcutContent?: JSX.Element | Array<JSX.Element>
}

const itemPickerRelativeStyle: BetterSystemStyleObject = {
  position: 'relative',
  width: '100%',
  cursor: 'text',
  display: 'flex',
}

export const DiscoveryInput: React.FC<DiscoveryInputProps> = ({
  inputRef,
  renderInput,
  newItemAttributes,
  omnibarText,
  setOmnibarText,
  defaultPlaceholder,
  isDisabled,
  createDraft,
  isFocused,
  omnibarMenu,
  setOmnibarMenu,
}) => {
  useEffect(() => {
    if (inputRef.current && isFocused) {
      inputRef.current?.focus()
    }
  }, [inputRef, isFocused])

  // When we use useRef, containerRef is not getting the correct ref in the board view.
  // Switching it to controlled ref.
  const [containerRef, onContainerRefChange] = useControlledRef<HTMLDivElement>()

  const startIssueCreator = useStartIssueCreator()
  const {navigationDispatch} = useStableTableNavigation()

  const groupedMenuItems: Array<Array<DiscoveryMenuItem>> = useMemo(() => {
    const shortcuts = {
      primary: 'Enter',
      secondary: `${isMacOS() ? '⌘' : 'Ctrl'}+Enter`,
    }
    const groupedItems = []
    const creationItems = []
    const {memex_omnibar_prioritize_create_issue} = getEnabledFeatures()
    const createIssueItem = {
      icon: IssueOpenedIcon,
      title: 'Create new issue',
      action: 'createIssue',
      shortcutContent: (
        <KeybindingHint keys={memex_omnibar_prioritize_create_issue ? shortcuts.primary : shortcuts.secondary} />
      ),
    }
    const createDraftItem = {
      icon: IssueDraftIcon,
      title: 'Create a draft',
      action: 'createDraft',
      shortcutContent: (
        <KeybindingHint keys={memex_omnibar_prioritize_create_issue ? shortcuts.secondary : shortcuts.primary} />
      ),
    }

    if (omnibarText.trim().length > 0) {
      creationItems.push(createDraftItem)
    }
    if (startIssueCreator) {
      creationItems.push(createIssueItem)
    }

    if (memex_omnibar_prioritize_create_issue) creationItems.reverse()

    // GroupedItems is an array of arrays so we can render them as groups in the menu separated by a divider
    groupedItems.push(creationItems)
    groupedItems.push([
      {
        icon: RepoIcon,
        title: 'Add item from repository',
        action: 'openSidePanel',
      },
    ])

    return groupedItems
  }, [startIssueCreator, omnibarText])

  const coordinates = useCoordinates(inputRef)

  const inputOnChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const value = e.target.value
      setOmnibarText(value)
      if (value.startsWith('#')) {
        setOmnibarMenu('repos')
      } else if (value.trim() === '') {
        setOmnibarMenu(null)
      } else {
        setOmnibarMenu('discovery')
      }
    },
    [setOmnibarText, setOmnibarMenu],
  )

  const createItem = useCallback(() => {
    if (isIssueOrPullRequestUrl(omnibarText)) {
      // Send pattern-matched issue and PR URLs straight through the createDraft plumbing, which automatically converts
      // to an memex item on the server if permissioned. We may not perfectly match urls here, and we don't catch
      // unauthorized issues/PRs, but the worst-case scenario is the user would need to convert to issue after the fact.
      createDraft(omnibarText)
    } else {
      if (startIssueCreator) {
        setOmnibarMenu(null)
        setOmnibarText('')

        startIssueCreator.start(
          {
            issueTitle: omnibarText,
          },
          newItemAttributes,
          inputRef,
          options => {
            if (options?.cancelled) {
              // Though `omnibarText` may be cleared elsewhere, its value here is preserved from before due to being inside a closure
              setOmnibarText(omnibarText)
            } else {
              requestAnimationFrame(() => {
                // Focus the row that was just added, the second column
                navigationDispatch(
                  moveTableFocus({
                    x: NavigationDirection.Second,
                    y: NavigationDirection.Last,
                    focusType: FocusType.Focus,
                  }),
                )
              })
            }
          },
        )
      }
    }
  }, [
    inputRef,
    newItemAttributes,
    omnibarText,
    startIssueCreator,
    setOmnibarText,
    navigationDispatch,
    setOmnibarMenu,
    createDraft,
  ])

  const {openPaneBulkAdd} = useSidePanel()

  const onSelectedItemChange = useCallback(
    async (item: DiscoveryMenuItem) => {
      if (!item) return

      switch (item.action) {
        case 'createDraft':
          setOmnibarText('')
          await createDraft(omnibarText)
          break
        case 'createIssue':
          setOmnibarText('')
          createItem()
          break
        case 'openSidePanel':
          openPaneBulkAdd(
            OmnibarDiscoverSuggestionsUI,
            undefined,
            item.title !== 'Add item from repository' ? item.title : undefined,
            newItemAttributes,
          )
          break
      }
    },
    [openPaneBulkAdd, newItemAttributes, omnibarText, setOmnibarText, createDraft, createItem],
  )
  // Comboxbox within useAutocomplete is how we get the item selection and keyboard navigation inside the picker list
  const {getInputProps, getListProps, getItemProps} = useAutocomplete<DiscoveryMenuItem>(
    {
      items: groupedMenuItems.flat(),
      onSelectedItemChange,
      isOpen: omnibarMenu === 'discovery',
    },
    inputRef,
  )

  const inputOnKeyDown = async (event: React.KeyboardEvent<HTMLInputElement>) => {
    const {memex_omnibar_prioritize_create_issue} = getEnabledFeatures()

    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    switch (event.key) {
      case 'Enter': {
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        const modifierKey = isMacOS() ? event.metaKey : event.ctrlKey

        if (modifierKey) {
          if (memex_omnibar_prioritize_create_issue) {
            createDraft(omnibarText)
          } else {
            createItem()
          }
          // Account for scenario where user has dismissed the menu (e.g. with `Esc`), and `Enter` should still work
        } else if (omnibarMenu === null) {
          if (memex_omnibar_prioritize_create_issue) {
            createItem()
          } else {
            createDraft(omnibarText)
          }
        }

        break
      }
      case 'Tab':
        if (!event.shiftKey && omnibarText.trim().length > 0) {
          event.preventDefault()
          setOmnibarText('')
          await createDraft(omnibarText, {shouldFocusInput: false})

          requestAnimationFrame(() => {
            // Focus the row that was just added, the second column
            navigationDispatch(
              moveTableFocus({
                x: NavigationDirection.Second,
                y: NavigationDirection.Last,
                focusType: FocusType.Focus,
              }),
            )
          })
        }
        break
      case 'Escape':
        // This component is currently used for both menu-less states and when the discovery menu appears
        // We should remedy that, but for now, only react to and prevent bubbling when discovery menu is open
        if (omnibarMenu === 'discovery') {
          setOmnibarMenu(null)
          event.stopPropagation()
        }
        break
      case 'ArrowDown':
      case 'ArrowUp':
        // Do not propagate arrow key presses when open, as
        // they're used for cell navigation.
        if (omnibarMenu === 'discovery') {
          event.stopPropagation()
        }
        break
    }
  }
  const inputCompositionProps = useIgnoreKeyboardActionsWhileComposing(inputOnKeyDown)

  const omnibarDescriptionId = useId()
  const input = isDisabled ? (
    <BaseCell aria-disabled="true" sx={{cursor: 'not-allowed', pl: '20px'}}>
      {defaultPlaceholder}
    </BaseCell>
  ) : (
    renderInput({
      ...getInputProps({
        onChange: inputOnChange,
      }),
      fontSize: 1,
      pl: '12px',
      lineHeight: 1.5,
      'aria-label': Resources.newItemPlaceholderAriaLabel,
      'aria-describedby': omnibarDescriptionId,
      autoComplete: 'off',
      value: omnibarText,
      ...inputCompositionProps,
    })
  )

  return (
    <Box sx={itemPickerRelativeStyle} ref={onContainerRefChange}>
      <OmnibarPlaceholder
        focusedPlaceholder={Resources.newItemPlaceholder}
        inputHasFocus={!!isFocused}
        value={omnibarText}
        descriptionId={omnibarDescriptionId}
        unfocusedPlaceholder={defaultPlaceholder}
      />
      {input}
      <DiscoveryMenu
        {...getListProps()}
        containerRef={containerRef}
        groupedItems={groupedMenuItems}
        getItemProps={getItemProps}
        itemOnMouseDown={item => {
          onSelectedItemChange(item)
        }}
        coordinates={coordinates}
        isOpen={omnibarMenu === 'discovery'}
      />
    </Box>
  )
}

interface DiscoveryMenuProps extends React.HTMLAttributes<HTMLUListElement> {
  groupedItems: Array<Array<DiscoveryMenuItem>>
  containerRef: React.RefObject<HTMLDivElement>
  coordinates: {top: number; left: number}
  getItemProps: (
    item: DiscoveryMenuItem,
    index: number,
    additionalHandlers?: GetItemPropsAdditionalHandlers,
  ) => React.LiHTMLAttributes<HTMLLIElement>
  itemOnMouseDown: (item: DiscoveryMenuItem) => void
  isOpen?: boolean
}

// @shiftkey note:
//
// I copy-pasted this component because the ref and forwardRef here seem required for the flow
// I'd love to remove this this but for now let's get this working...
const DiscoveryMenu = forwardRef<HTMLUListElement, DiscoveryMenuProps>(
  ({groupedItems, getItemProps, itemOnMouseDown, containerRef, coordinates, isOpen, ...listProps}, forwardedRef) => {
    const ref = useRef<HTMLUListElement>(null)
    useRefObjectAsForwardedRef(forwardedRef, ref)

    const {adjustPickerPosition} = useAdjustPickerPosition(containerRef, ref, true, [coordinates, groupedItems], {
      yAlign: 'bottom',
    })

    let itemIndex = 0

    return (
      <Portal onMount={adjustPickerPosition}>
        <PickerList
          {...listProps}
          {...testIdProps('discovery-menu')}
          ref={ref}
          sx={{
            display: isOpen ? 'block' : 'none',
            p: [null, 0],
            width: [null, '300px'],
            maxWidth: [null, '300px'],
          }}
          aria-label="Discovery menu"
        >
          {groupedItems.map((group, groupIndex) => {
            return (
              <Fragment key={groupIndex++}>
                {group.map((item, index) => {
                  return (
                    <Fragment key={index++}>
                      <PickerItem
                        style={{
                          padding: 8,
                        }}
                        value={item.title}
                        {...testIdProps('issue-picker-item')}
                        {...getItemProps(item, itemIndex++, {
                          onMouseDown: () => itemOnMouseDown(item),
                        })}
                      >
                        <Box sx={{justifyContent: 'space-between', overflow: 'hidden', flex: 1, display: 'flex'}}>
                          <span>
                            <Octicon icon={item.icon} sx={{ml: 2, color: 'fg.muted'}} />
                            <Text sx={{ml: 2, color: 'fg.muted', fontSize: 1}}>{item.title}</Text>
                          </span>
                          <span style={{display: 'flex', alignItems: 'center'}}>{item.shortcutContent}</span>
                        </Box>
                      </PickerItem>
                    </Fragment>
                  )
                })}
                {groupIndex !== group.length && <ActionList.Divider sx={{margin: 0}} />}
              </Fragment>
            )
          })}
        </PickerList>
      </Portal>
    )
  },
)

DiscoveryMenu.displayName = 'DiscoveryMenu'

const subscribeToDocumentResize = (notify: () => void) => {
  const resizeObserver = new ResizeObserver(() => requestAnimationFrame(notify))
  resizeObserver.observe(document.documentElement)
  return () => {
    resizeObserver.unobserve(document.documentElement)
    resizeObserver.disconnect()
  }
}
function useCoordinates(inputRef: React.RefObject<HTMLDivElement>) {
  const coordinatesCache = useRef({top: 0, left: 0})
  return useSyncExternalStore(subscribeToDocumentResize, () => {
    const previousValue = coordinatesCache.current
    if (inputRef.current) {
      const {top, left} = inputRef.current.getBoundingClientRect()
      if (top !== previousValue.top || left !== previousValue.left) {
        coordinatesCache.current = {top, left}
      }
    }
    return coordinatesCache.current
  })
}
