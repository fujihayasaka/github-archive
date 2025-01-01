import {AiModelIcon} from '@primer/octicons-react'
import {Spinner, Stack} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {clsx} from 'clsx'
import invariant from 'tiny-invariant'

import {useCurrentCallback} from '../hooks/use-current-callback'
import type {SelectorCustomModel} from '../types'
import {ModelSelectorConfig} from './ModelSelectorConfig'
import styles from './ModelSelectorPane.module.css'

export function ModelSelectorPane({
  loading = false,
  editable,
  models,
  selected,
  onLabelUpdate,
  onSelect,
  disabled,
}: {
  models: SelectorCustomModel[]
  selected: Array<SelectorCustomModel['slug']>
  onSelect?: (selected: boolean, model: SelectorCustomModel) => void
  loading?: boolean
  onLabelUpdate?: (newValue: string, model: SelectorCustomModel) => void
  editable?: boolean
  disabled?: boolean
}) {
  const isEmpty = !models.length || loading

  invariant(editable === undefined || onLabelUpdate, 'onLabelUpdate must be provided if editable is true')
  invariant(isEmpty || onSelect, 'onSelect must be provided if items are not empty')

  // Note; ModelSelectorConfig makes use of React.memo, and unstable callbacks would be a deopt
  // so we use useCurrentCallback here to ensure that the callbacks are stable.
  const onSelectHandler = useCurrentCallback(onSelect)
  const onLabelUpdateHandler = useCurrentCallback(onLabelUpdate)

  return (
    <div
      role={!isEmpty ? 'group' : undefined}
      className={clsx(styles.ModelSelectorPane, {
        [styles.ModelSelectorPaneEmpty]: isEmpty,
      })}
    >
      {isEmpty ? (
        <ModelSelectorPaneBlankslate loading={loading} />
      ) : (
        <Stack gap="condensed">
          {models.map(model => (
            <ModelSelectorConfig
              key={model.slug}
              model={model}
              onSave={onLabelUpdateHandler}
              onSelect={onSelectHandler}
              selected={selected.includes(model.slug)}
              editable={editable}
              disabled={disabled}
            />
          ))}
        </Stack>
      )}
    </div>
  )
}

function ModelSelectorPaneBlankslate({loading}: {loading: boolean}) {
  return (
    <Blankslate>
      <Blankslate.Visual>{loading ? <Spinner size="small" /> : <AiModelIcon size="small" />}</Blankslate.Visual>
      <Blankslate.Description>
        {loading ? 'Loading...' : 'Add a valid key to see available models'}
      </Blankslate.Description>
    </Blankslate>
  )
}
