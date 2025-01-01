import type {Model} from '@github-ui/marketplace-common'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Button, SelectPanel} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useState, type HTMLAttributes} from 'react'
import invariant from 'tiny-invariant'
import {PublisherAvatar} from '../../../components/PublisherAvatar'
import type {ModelDetails, ModelItemInput} from '../../../types'
import {userHasAccessToModel} from '../../../utils/model-access'
import {normalizeModelPublisher} from '../../../utils/normalize-model-strings'
import {useModelDetailsQuery} from '../hooks/use-model-details-query'

import styles from './ModelPicker.module.css'

export default function ModelPicker({
  modelId,
  restrictedModels,
  onSelect,
}: {
  modelId?: string
  restrictedModels: string[]
  onSelect(model: Model, modelDetails?: ModelDetails): void
}) {
  const {data: models, isLoading: isLoadingModels} = useQuery<Model[]>({
    queryKey: ['github-models', 'models'],
    initialData: [],
    async queryFn() {
      const res = await verifiedFetchJSON('/marketplace/models')
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
  })

  const [showPanel, setShowPanel] = useState(false)
  const [filter, setFilter] = useState('')

  const [selectedModel, setSelectedModel] = useState<Model>(() => models?.find(m => m.id === modelId) || ({} as Model))

  const selected = useMemo<ModelItemInput | undefined>(() => {
    const s = models.find(item => item.id === selectedModel?.id)
    if (s) return modelToItem(s)
    return undefined
  }, [models, selectedModel?.id])

  const onSelectHandler = useCallback(
    (itemInput: ItemInput | undefined) => {
      if (itemInput && itemInput.item) {
        setSelectedModel(itemInput.item as Model)
      }
    },
    [setSelectedModel],
  )

  const filteredModels = useMemo(() => {
    const filterValue = filter.toLowerCase()

    return models.filter(
      m =>
        m.task === 'chat-completion' &&
        (m.friendly_name.toLowerCase().includes(filterValue) ||
          normalizeModelPublisher(m.publisher).toLowerCase().includes(filterValue)) &&
        userHasAccessToModel(m, restrictedModels),
    )
  }, [filter, models, restrictedModels])

  // Important: avoid changing this const's referential equality, as it triggers a scrollIntoView.
  // For example, avoid defining a `.selected` property on the object.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/FilteredActionList/FilteredActionListWithModernActionList.tsx#L137
  const items = useMemo<ModelItemInput[]>(() => {
    return filteredModels.map(modelToItem)
  }, [filteredModels])

  useEffect(() => {
    if (showPanel && selected) {
      requestAnimationFrame(() => {
        document.querySelector(`[data-id="${selected.id}"]`)?.scrollIntoView({
          behavior: 'instant',
        })
      })
    }
  }, [showPanel, selected])

  const {data: modelDetails, isFetching: isFetchingModelDetails} = useModelDetailsQuery(
    selectedModel?.registry,
    selectedModel?.name,
  )

  useEffect(() => {
    if (isFetchingModelDetails || !modelDetails) {
      return
    }

    if (selectedModel.id === modelId) {
      setShowPanel(false)
      return
    }

    onSelect(selectedModel, modelDetails)
  }, [isFetchingModelDetails, selectedModel, modelId, modelDetails, onSelect])

  // Using the renderAnchor prop gives us a lot for free, like accessibility props.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/AnchoredOverlay/AnchoredOverlay.tsx#L197-L204
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/SelectPanel/SelectPanel.tsx#L379
  const renderAnchor = useCallback(
    (props: HTMLAttributes<HTMLButtonElement>) => {
      return <SelectPanelAnchor buttonProps={props} selected={selectedModel} />
    },
    [selectedModel],
  )

  return (
    <SelectPanel
      title="Select model"
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
    />
  )
}

function SelectPanelAnchor({buttonProps, selected}: {buttonProps: HTMLAttributes<HTMLButtonElement>; selected: Model}) {
  // Intentionally omitting the `children` prop—we're rendering a custom element below.
  const {children, ...bProps} = buttonProps

  // TODO: buttonProps includes `ref: HTMLButtonElement`, even though Primer's types don't expose it.
  // See: https://github.com/primer/react/blob/308fe82909f3d922be0a6582f83e96798678ec78/packages/react/src/AnchoredOverlay/AnchoredOverlay.tsx#L198
  // The rendered anchor *must* receive this ref—it tells SelectPanel where to anchor.
  // If cherry-picking props later, make sure to forward the ref to the button.
  const ref = (bProps as {ref?: React.Ref<HTMLButtonElement>}).ref
  invariant(ref, 'ref must be passed to SelectPanelAnchor')

  const extraClassNames = 'className' in bProps && (bProps.className as string)

  return (
    <Button
      {...bProps}
      trailingAction={TriangleDownIcon}
      alignContent="start"
      className={clsx('d-flex gap-2 flex-items-center', styles.button, extraClassNames)}
      labelWrap
      leadingVisual={selected ? <ModelLeadingVisual model={selected} /> : undefined}
    >
      <div className={styles.dropdown}>{selected.name ? selected.friendly_name : 'Select model'}</div>
    </Button>
  )
}

function ModelLeadingVisual({model}: {model: Model}) {
  return (
    <PublisherAvatar
      logoUrl={model.logo_url}
      darkModeIcon={model.dark_mode_icon}
      publisher={model.publisher}
      size={18}
    />
  )
}

function modelToItem(model: Model): ModelItemInput {
  return {
    id: model.id,
    leadingVisual() {
      return <ModelLeadingVisual model={model} />
    },
    text: model.friendly_name,
    item: model,
  }
}
