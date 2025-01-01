import {useIgnoreKeyboardActionsWhileComposing} from '@github-ui/use-ignore-keyboard-actions-while-composing'
import {useTrackingRef} from '@github-ui/use-tracking-ref'
import {useRefObjectAsForwardedRef} from '@primer/react'
import type {ForwardRefComponent} from '@radix-ui/react-polymorphic'
import {forwardRef, useCallback, useEffect, useId, useMemo, useRef, useState} from 'react'

import {CommandEvent, CommandEventHandlersMap} from '../command-event'
import type {CommandId} from '../commands'
import {CommandsContextProvider, useCommandsContext} from '../commands-context'
import {useRegisterCommands} from '../commands-registry'
import {recordCommandTriggerEvent} from '../metrics'
import {useDetectConflicts} from '../use-detect-conflicts'
import {useOnKeyDown} from '../use-on-key-down'

export interface ScopedCommandsProps extends Omit<LimitKeybindingScopeProps, 'commandIds'> {
  /** Map of command IDs to the corresponding event handler. */
  commands: CommandEventHandlersMap
}

// See export at end of file for docstring
const ScopedCommandsComponent = forwardRef(({commands, ...props}, forwardedRef) => {
  // We store the commands object in a ref so the context won't change on every render and recalculate the whole child tree
  const commandsRef = useTrackingRef(commands)

  const parentContext = useCommandsContext()

  const triggerCommand = useCallback(
    <T extends CommandId>(commandId: T, domEvent: KeyboardEvent | MouseEvent) => {
      const handler = commandsRef.current[commandId]

      if (handler) {
        const event = new CommandEvent(commandId)
        try {
          handler(event)
        } finally {
          recordCommandTriggerEvent(event, domEvent)
        }
      } else {
        // no handler here, pass it on up
        parentContext.triggerCommand(commandId, domEvent)
      }
    },
    [commandsRef, parentContext],
  )

  useDetectConflicts('scoped', commands)

  useRegisterCommands(commands)

  const [limitedScopeMap, setLimitedScopeMap] = useState<ReadonlyMap<string, CommandId[]>>(new Map())
  const registerLimitedKeybindingScope = useCallback(
    (uniqueKey: string, newIds: CommandId[]) =>
      setLimitedScopeMap(map => {
        const currentIds = map.get(uniqueKey)
        // avoid unnecessary updates if the new value is the same as the old
        if (newIds.length === currentIds?.length && newIds.every((id, i) => currentIds[i] === id)) return map
        return new Map([...map, [uniqueKey, newIds]])
      }),
    [],
  )

  /** The set of command IDs that are not limited in scope and should be registered at this level. */
  const commandIdsWithoutLimitedScope = useMemo(() => {
    const commandIdsWithLimitedScope = new Set(Array.from(limitedScopeMap.values()).flat())
    return CommandEventHandlersMap.keys(commands).filter(id => !commandIdsWithLimitedScope.has(id))
  }, [commands, limitedScopeMap])

  const contextValue = useMemo(
    () => ({triggerCommand, registerLimitedKeybindingScope}),
    [triggerCommand, registerLimitedKeybindingScope],
  )

  return (
    <CommandsContextProvider value={contextValue}>
      <KeybindingScope ref={forwardedRef} commandIds={commandIdsWithoutLimitedScope} {...props} />
    </CommandsContextProvider>
  )
}) as ForwardRefComponent<'div', ScopedCommandsProps>
ScopedCommandsComponent.displayName = 'ScopedCommands'

export interface LimitKeybindingScopeProps {
  /** List of command IDs to be scope-limited by this component. */
  commandIds: CommandId[]
  /**
   * Execute command handlers even if the underlying keyboard event was `defaultPrevented`.
   * @deprecated Avoid: Event handlers should always respect `defaultPrevented`. This escape hatch is provided for
   * backwards compatibility where command keybindings conflict with other event handling code. Eventually the
   * conflicts should be resolved and this prop removed.
   * @default false
   */
  triggerOnDefaultPrevented?: boolean
  // 🧙 You Shall Not Pass:
  onCompositionStart?: never
  onCompositionEnd?: never
  onKeyDown?: never
}

/**
 * Internal: binds keyboard event listeners for the given command IDs, using handlers from context.
 *
 * Unlike `LimitKeybindingScope`, this doesn't register the commands as limited-scope, so it can be shared with
 * `ScopedCommands`.
 */
const KeybindingScope = forwardRef(({commandIds: commands, as, triggerOnDefaultPrevented, ...props}, forwardedRef) => {
  const parentContext = useCommandsContext()

  const onKeyDown = useOnKeyDown(commands, parentContext.triggerCommand, {triggerOnDefaultPrevented})

  const keyDownProps = useIgnoreKeyboardActionsWhileComposing(onKeyDown)

  const containerRef = useRef<HTMLDivElement>(null)
  useRefObjectAsForwardedRef(forwardedRef, containerRef)

  // Events first bubble up the DOM tree, then React handles them at the document level and rebuilds a 'synthetic'
  // JSX tree. If we only handle our events with React, we cannot stop native DOM handlers from capturing those events
  // first, even if we `stopPropagation`. For example, `@primer/behaviors` uses DOM handlers. So must handle events
  // with DOM handlers so we can 'get to them first'. However, this is not good enough because with scoped commands we
  // want the user to be able to fire commands when their focus is inside a menu overlay. This only works with React
  // handlers because overlays are rendered inside Portals. So we must bind _both_ DOM and React handlers, allowing
  // `useOnKeyDown` to handle ignoring duplicates.
  useEffect(() => {
    const target = containerRef.current
    // we are lying by passing DOM events to a React handler, but it works in this case because the handler we passed in can accept DOM events
    const handler = keyDownProps.onKeyDown as unknown as (e: KeyboardEvent) => void
    if (!target) return

    target.addEventListener('keydown', handler)
    return () => target.removeEventListener('keydown', handler)
  })

  // Typically we want to avoid `display: contents` due to its rocky history in terms of web browser accessibility
  // support. We've seen bugs appear, get fixed, and then regress again with this property. Unfortunately, there's no
  // good alternative here. We must wrap contents in some element to intercept keyboard shortcuts, and wrapping
  // contents in an element inherently introduces potential style and layout breaks. The only way to avoid that is
  // with `display: contents`; otherwise consumers will have to deal with fixing everything that this breaks every time
  // they use this component and they will be discouraged from adopting the new platform.
  //
  // If `as` is set to something other than `div`, or if a className was passed to explicitly set some styling, we don't do this,
  // because we assume the consumer is now thinking about styling and expects an element to appear.
  //
  // IMPORTANT: even with this in place, adding a div can still break some css rules, so be careful when using this.
  // for example:
  // - If the wrapped component has a selector such as `:not(:first-child)`, it will break since it will now be the first child
  // - If the parent has any direct decendant selectors, they will now be broken
  //
  // Before using, the best approach is to inspect the elements in the browser dev tools and look for any css rules that
  // might be affected by this change.
  const style = as !== undefined || props.className !== undefined ? undefined : {display: 'contents'}
  const Wrapper = as ?? 'div'

  return <Wrapper style={style} {...props} {...keyDownProps} ref={containerRef} />
}) as ForwardRefComponent<'div', LimitKeybindingScopeProps>
KeybindingScope.displayName = 'KeyboardScope'

/**
 * By default, `ScopedCommands` will bind keybinding handlers for its entire child tree. This usually works fine, but
 * sometimes you need to render a command-bound component outside of the desired keybinding area. For this case, you
 * can limit the keybinding area of certain commands by wrapping the desired area in `ScopedCommands.LimitKeybindingScope`.
 *
 * For example, here the `CommandButton` component has access to the "format bold" command but is not included in the
 * keybinding scope -- the keybinding for bold formatting can only be triggered when focus is inside the input. On the
 * other hand, the "submit" keybinding can be triggered anywhere inside the scope:
 *
 * ```
 * <ScopedCommands commands={{'comment-box:format-bold': handleFormatBold, 'comment-box:submit': handleSubmit}}>
 *   <CommandButton commandId="comment-box:format-bold" />
 *
 *   <ScopedCommands.LimitKeybindingScope commands={["comment-box:format-bold"]}>
 *     <textarea />
 *   </ScopedCommands.LimitKeybindingScope>
 * </ScopedCommands>
 * ```
 */
const LimitKeybindingScope = forwardRef(({commandIds: commands, ...props}, forwardedRef) => {
  const parentContext = useCommandsContext()

  // Careful: registering these commands triggers the ScopedCommands component to update state which in turn causes
  // this component to re-render - this can easily cause an infinite render loop if we aren't cautious
  const uniqueKey = useId()
  useEffect(
    () => parentContext.registerLimitedKeybindingScope(uniqueKey, commands),
    [parentContext, commands, uniqueKey],
  )
  // Cleanup is a separate effect to avoid a dependency on `commands`; this way we don't double-call on every change
  // (once with an empty array and then again with the new array)
  // This also allows for optimizing inside ScopedCommands to avoid extra renders when the array values don't change
  useEffect(() => () => parentContext.registerLimitedKeybindingScope(uniqueKey, []), [parentContext, uniqueKey])

  return <KeybindingScope ref={forwardedRef} commandIds={commands} {...props} />
}) as ForwardRefComponent<'div', LimitKeybindingScopeProps>
LimitKeybindingScope.displayName = 'LimitKeybindingScope'

/**
 * Provide command handlers that only work when focus is within a certain part of the React component tree.
 *
 * NOTE: By default this component will wrap contents in a `div` with `display: contents`. In certain cases this breaks
 * the page's HTML structure (for example, when wrapping list items or table cells). In this case the component element
 * type can be overridden with `as`.
 * @example
 * <ScopedCommands commands={{
 *   'comment-box:format-bold': handleFormatBold
 * }}>
 *   <textarea></textarea>
 * </ScopedCommands>
 */
export const ScopedCommands = Object.assign(ScopedCommandsComponent, {LimitKeybindingScope})
