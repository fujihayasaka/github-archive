import type {Model} from '@github-ui/marketplace-common'
import {modelsCatalogPath, type Repository} from '@github-ui/paths'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {testIdProps} from '@github-ui/test-id-props'
import {InfoIcon, TriangleDownIcon} from '@primer/octicons-react'
import {IconButton, Button, SelectPanel, useResponsiveValue, type ResponsiveValue} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useRef, useState, type HTMLAttributes} from 'react'
import invariant from 'tiny-invariant'
import type {RepoModel} from '../../../../github-models-repo/types'
import {PublisherAvatar} from '../../../components/PublisherAvatar'
import {SidebarSelectionOptions, type GettingStartedPayload, type ModelItemInput} from '../../../types'
import {userHasAccessToModel} from '../../../utils/model-access'
import {normalizeModelPublisher} from '../../../utils/normalize-model-strings'

import styles from './ModelSwitcher.module.css'

export default function ModelSwitcher({
  model,
  onSelect,
  handleSetSidebarTab,
  variant,
  repository,
  availableModels,
  isLoadingModels,
}: {
  model?: Model
  onSelect(model: Model): void
  handleSetSidebarTab: (newTab: SidebarSelectionOptions) => void
  variant?: 'default' | 'compare_button'
  repository?: Repository
  availableModels: Model[] | RepoModel[]
  isLoadingModels: boolean
}) {
  const {restrictedModels} = useRoutePayload<GettingStartedPayload>()

  const [showPanel, setShowPanel] = useState(false)
  const [filter, setFilter] = useState('')

  const selected = useMemo<ModelItemInput | undefined>(() => {
    if (model) return modelToItem(model)
    return undefined
  }, [model])

  const onSelectCurrentHandler = useCurrentCallback(onSelect)
  const onSelectHandler = useCallback(
    (selectedModel: ItemInput | undefined) => {
      if (selectedModel && selectedModel.item) {
        onSelectCurrentHandler(selectedModel.item as Model)
      } else if (variant === 'compare_button' && !selectedModel && model) {
        onSelectCurrentHandler(model)
      }
    },
    [onSelectCurrentHandler, model, variant],
  )

  const filteredModels = useMemo(() => {
    const filterValue = filter.toLowerCase()
    return availableModels.filter(
      m =>
        m.task === 'chat-completion' &&
        (m.friendly_name.toLowerCase().includes(filterValue) ||
          normalizeModelPublisher(m.publisher).toLowerCase().includes(filterValue)) &&
        userHasAccessToModel(m, restrictedModels),
    )
  }, [availableModels, filter, restrictedModels])

  // Important: avoid changing this const's referential equality, as it triggers a scrollIntoView.
  // For example, avoid defining a `.selected` property on the object.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/FilteredActionList/FilteredActionListWithModernActionList.tsx#L137
  const items = useMemo<ModelItemInput[]>(() => {
    return filteredModels.map(modelToItem)
  }, [filteredModels])

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

  // Using the renderAnchor prop gives us a lot for free, like accessibility props.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/AnchoredOverlay/AnchoredOverlay.tsx#L197-L204
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/SelectPanel/SelectPanel.tsx#L379
  const renderAnchor = useCallback(
    (props: HTMLAttributes<HTMLButtonElement>) => {
      return <SelectPanelAnchor buttonProps={props} selected={selected?.item as Model | RepoModel} variant={variant} />
    },
    [selected?.item, variant],
  )

  return (
    <div className="d-flex flex-items-center">
      <SelectPanel
        title={variant === 'compare_button' ? 'Select model' : 'Switch model'}
        placeholderText="Search"
        items={items}
        loading={isLoadingModels}
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
        secondaryAction={!repository ? <ViewModeModelsAction /> : undefined}
      />
      {model && variant !== 'compare_button' && (
        <div className="hide-lg hide-xl ml-2">
          <IconButton
            icon={InfoIcon}
            aria-label="Show model info"
            onClick={() => handleSetSidebarTab(SidebarSelectionOptions.DETAILS)}
          />
        </div>
      )}
    </div>
  )
}

function SelectPanelAnchor({
  buttonProps,
  selected,
  variant,
}: {
  buttonProps: HTMLAttributes<HTMLButtonElement>
  selected?: Model | RepoModel
  variant?: 'default' | 'compare_button'
}) {
  // Intentionally omitting the `children` prop—we're rendering a custom element below.
  const {children, ...bProps} = buttonProps

  // TODO: buttonProps includes `ref: HTMLButtonElement`, even though Primer's types don't expose it.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/AnchoredOverlay/AnchoredOverlay.tsx#L198
  // The rendered anchor *must* receive this ref—it tells SelectPanel where to anchor.
  // If cherry-picking props later, make sure to forward the ref to the button.
  const ref = (bProps as {ref?: React.Ref<HTMLButtonElement>}).ref
  invariant(ref, 'ref must be passed to SelectPanelAnchor')

  const extraClassNames = 'className' in bProps && (bProps.className as string)

  if (variant === 'compare_button') {
    return (
      <Button
        {...bProps}
        variant="default"
        aria-label="Select model to compare"
        {...testIdProps('compare-model-button')}
      >
        Compare
      </Button>
    )
  }

  return (
    <Button
      {...bProps}
      variant={selected ? 'default' : 'primary'}
      aria-label="Switch model"
      trailingAction={TriangleDownIcon}
      leadingVisual={selected ? <ModelLeadingVisual model={selected} /> : undefined}
      alignContent="start"
      className={clsx(
        'd-flex gap-2 flex-items-center',
        styles.selectAnchor,
        {
          ['bgColor-default']: selected,
        },
        extraClassNames,
      )}
      {...testIdProps('model-friendly-name')}
    >
      <div className={styles.modelName}>
        <span className={selected && 'fgColor-muted'}>Model:</span>{' '}
        {selected ? selected.friendly_name : 'Select a Model'}
      </div>
    </Button>
  )
}

function ViewModeModelsAction() {
  const responsiveButtonSizes: ResponsiveValue<'small' | 'medium'> = {narrow: 'medium', regular: 'small'}
  const linkSize = useResponsiveValue(responsiveButtonSizes, 'small')

  return (
    <SelectPanel.SecondaryActionLink href={modelsCatalogPath()} size={linkSize}>
      View all models
    </SelectPanel.SecondaryActionLink>
  )
}

function ModelLeadingVisual({model}: {model: Model | RepoModel}) {
  return (
    <PublisherAvatar
      logoUrl={model.logo_url}
      darkModeIcon={model.dark_mode_icon}
      publisher={model.publisher}
      size={18}
    />
  )
}

function modelToItem(model: Model | RepoModel): ModelItemInput {
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
