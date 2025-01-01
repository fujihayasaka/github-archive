import {normalizeModelPublisher} from '@github-ui/github-models/NormalizeModels'
import {clsx} from 'clsx'
import {PublisherAvatar} from '@github-ui/github-models/PublisherAvatar'
import {AlertIcon, TriangleDownIcon} from '@primer/octicons-react'
import {AnchoredOverlay, Button, type ButtonProps, SelectPanel, Truncate} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {
  useCallback,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ElementType,
  type HTMLAttributes,
} from 'react'
import invariant from 'tiny-invariant'
import type {RepoModel} from '../../../types'
import {useModels} from '../contexts/ModelsContext'

import styles from './ModelPicker.module.css'
import {Blankslate} from '@primer/react/experimental'

type Item = {
  id: string
  leadingVisual: ElementType
  text: string
  item: RepoModel
}

export default function ModelPicker({
  selectedModel,
  onSelect,
  buttonProps: primerButtonProps,
}: {
  selectedModel?: RepoModel | undefined
  onSelect(model: RepoModel): void
  buttonProps?: ButtonProps
}) {
  const [showPanel, setShowPanel] = useState(false)

  const models = useModels()

  const [filter, setFilter] = useState('')
  const deferredFilter = useDeferredValue(filter)
  const filteredModels = useMemo(() => {
    const filterValue = deferredFilter.toLowerCase()

    return models.filter(
      m =>
        m.friendly_name.toLowerCase().includes(filterValue) ||
        normalizeModelPublisher(m.publisher).toLowerCase().includes(filterValue),
    )
  }, [deferredFilter, models])

  // Important: avoid changing this const's referential equality, as it triggers a scrollIntoView.
  // For example, avoid defining a `.selected` property on the object.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/FilteredActionList/FilteredActionListWithModernActionList.tsx#L137
  const items = useMemo<Item[]>(() => {
    return filteredModels.map(repoModelToItem)
  }, [filteredModels])

  const onSelectCurrentHandler = useCurrentCallback(onSelect)
  const onSelectHandler = useCallback(
    (item: ItemInput | undefined) => {
      if (item?.item) {
        onSelectCurrentHandler(item.item as RepoModel)
      }
    },
    [onSelectCurrentHandler],
  )

  const selected = useMemo(() => {
    const s = models.find(item => item.id === selectedModel?.id)
    if (s) return repoModelToItem(s)
    return undefined
  }, [models, selectedModel?.id])

  useEffect(() => {
    if (showPanel && selected) {
      requestAnimationFrame(() => {
        const node = document.querySelector(`[data-id="${selected.id}"]`)
        if (!node) return
        const container = getNearestScrollContainer(node)

        // If there is no scroll container, say a list with only 2 items in it.
        // fall back to the browser behaviour. Note this may cause the viewport to scroll
        if (!container) {
          node?.scrollIntoView({
            behavior: 'instant',
          })
          return
        }

        container.scrollTop = node.getBoundingClientRect().top - container.getBoundingClientRect().top
      })
    }
  }, [showPanel, selected])

  // Using the renderAnchor prop gives us a lot for free—especially accessibility props:
  // Ideally, this wouldn't need to be so custom, but we need access to the full selected item,
  // the default button's children is just "selected.text", but we need to render things
  // like the publisher avatar and model name.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/AnchoredOverlay/AnchoredOverlay.tsx#L197-L204
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/SelectPanel/SelectPanel.tsx#L379
  // TODO: Can we push some of this into Primer, letting it pass the selected item?
  const renderAnchor = useCallback(
    (htmlButtonProps: HTMLAttributes<HTMLButtonElement>) => {
      return <SelectPanelAnchor {...primerButtonProps} htmlButtonProps={htmlButtonProps} selected={selectedModel} />
    },
    [primerButtonProps, selectedModel],
  )

  if (!models.length) {
    return (
      <div className={styles.modelPickerContainer}>
        <AnchoredOverlay
          open={showPanel}
          onOpen={() => setShowPanel(true)}
          onClose={() => setShowPanel(false)}
          renderAnchor={renderAnchor}
          width="medium"
        >
          <Blankslate>
            <Blankslate.Visual>
              <AlertIcon size={32} aria-hidden="true" />
            </Blankslate.Visual>
            <Blankslate.Heading>No models available</Blankslate.Heading>
            <Blankslate.Description>
              This repository has no allowed models. Contact your organization administrator for more information.
            </Blankslate.Description>
          </Blankslate>
        </AnchoredOverlay>
      </div>
    )
  }

  return (
    <div className={styles.modelPickerContainer}>
      <SelectPanel
        title={selectedModel?.friendly_name || 'Select model'}
        placeholder="Select model"
        items={items}
        open={showPanel}
        onOpenChange={setShowPanel}
        onFilterChange={setFilter}
        selected={selected}
        onSelectedChange={onSelectHandler}
        overlayProps={{width: 'medium', height: 'large'}}
        textInputProps={{
          ['aria-label']: 'Filter models',
        }}
        renderAnchor={renderAnchor}
      />
    </div>
  )
}

function SelectPanelAnchor({
  // Intentionally omitting the `children` prop—we're rendering a custom element below.
  htmlButtonProps: {children, ...htmlButtonProps},
  selected,
  ...primerButtonProps
}: Omit<ButtonProps, 'children'> & {
  htmlButtonProps: HTMLAttributes<HTMLButtonElement>
  selected?: RepoModel
}) {
  // TODO: buttonProps includes `ref: HTMLButtonElement`, even though Primer's types don't expose it.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/AnchoredOverlay/AnchoredOverlay.tsx#L198
  // The rendered anchor *must* receive this ref—it tells SelectPanel where to anchor.
  // If cherry-picking props later, make sure to forward the ref to the button.
  const ref = (htmlButtonProps as {ref?: React.Ref<HTMLButtonElement>}).ref
  invariant(ref, 'ref must be passed to SelectPanelAnchor')

  const htmlButtonPropsClassName = 'className' in htmlButtonProps && (htmlButtonProps.className as string)
  const primerButtonPropsClassName = 'className' in primerButtonProps && (primerButtonProps.className as string)

  const displayName = selected?.friendly_name || 'Select model'

  return (
    <Button
      trailingAction={TriangleDownIcon}
      alignContent="start"
      labelWrap
      {...primerButtonProps}
      {...htmlButtonProps}
      className={clsx(styles.modelPickerName, {
        [htmlButtonPropsClassName || '']: htmlButtonPropsClassName,
        [primerButtonPropsClassName || '']: primerButtonPropsClassName,
      })}
      leadingVisual={selected ? <ModelLeadingVisual model={selected} /> : undefined}
    >
      <Truncate maxWidth="100%" title={displayName}>
        {displayName}
      </Truncate>
    </Button>
  )
}

function ModelLeadingVisual({model}: {model: RepoModel}) {
  return (
    <PublisherAvatar
      logoUrl={model.logo_url}
      darkModeIcon={model.dark_mode_icon}
      publisher={model.publisher}
      size={18}
    />
  )
}

function repoModelToItem(model: RepoModel): Item {
  return {
    id: model.id,
    leadingVisual() {
      return <ModelLeadingVisual model={model} />
    },
    text: model.friendly_name,
    item: model,
  }
}

/**
 * A helper hook that keeps a stable reference to a function, that when invoked
 * will always call the latest version of the callback provided.
 * This is useful when you have a callback that is used in a dependency array, or prop
 * to another component that may expect a stable reference, or a callback that is not stable.
 *
 * @example
 *
 * ```tsx
 * function MyComponent(props) {
 *   const callback = useCurrentCallback(props.unstableCallback)
 *   return <Button onClick={callback}>Click me</Button>
 * }
 * ```
 */
// `: any` here gives us the ability to type narrow, where `: unknown` would not
// eg: const cb = useCurrentCallback((foo: string) => boolean)
//          ^? (foo: string) => boolean
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function useCurrentCallback<T extends (...args: any[]) => any>(callback: T): T {
  const currentCallback = useRef<T | null>(callback)
  currentCallback.current = callback
  return useCallback((...args: Parameters<T>) => currentCallback.current!(...args), []) as T
}

function getNearestScrollContainer(element: Element, maxDepth = 5) {
  let currentElement: Element | null = element
  let depth = 0
  while (currentElement && depth < maxDepth) {
    if (currentElement.scrollHeight > currentElement.clientHeight) {
      return currentElement
    }
    currentElement = currentElement.parentElement
    depth++
  }
  return null
}
