import {Checkbox, Label, Stack} from '@primer/react'
import {clsx} from 'clsx'
import type {ReactEventHandler} from 'react'
import {memo, useCallback, useId, useRef} from 'react'

import type {SelectorCustomModel} from '../types'
import {InlineEdit} from './InlineEdit'
import styles from './ModelSelectorConfig.module.css'

export const ModelSelectorConfig = memo(ModelSelectorConfigImpl)

function ModelSelectorConfigImpl({
  model,
  selected,
  editable,
  disabled,
  onSelect,
  onSave,
}: {
  model: SelectorCustomModel
  selected?: boolean // Defaults to false
  editable?: boolean
  disabled?: boolean
  /**
   * A model is always selectable, except when it is deprecated.
   * Editable has no barings on selection.
   */
  onSelect: (checked: boolean, model: SelectorCustomModel) => void
  onSave?: (newValue: string, model: SelectorCustomModel) => void
}) {
  const id = useId()

  const checkboxRef = useRef<HTMLInputElement>(null)

  /*
  The current behavior is that you cannot "select" a deprecated model,
  but you can still edit the label of a model that is deprecated.
  Right now being disabled is the same as being deprecated. But semantically,
  they are different.
  */
  const isDeprecated = model.deprecated === true
  const isDisabled = isDeprecated || disabled
  const isEditable = !disabled && editable === true

  const fresh = !model.deprecated && model.fresh
  const hasName = !!model.name?.trim().length

  const displayName = model.name ?? model.slug

  const ariaLabel = [fresh && 'New model', isDeprecated && 'Deprecated model', displayName].filter(Boolean).join(' ')

  const selectHandler = useCallback<ReactEventHandler<HTMLInputElement>>(
    event => {
      onSelect(event.currentTarget.checked, model)
    },
    [onSelect, model],
  )

  const saveHandler = useCallback(
    (newValue: string) => {
      onSave?.(newValue, model)
    },
    [onSave, model],
  )

  return (
    <Stack
      align="center"
      direction="horizontal"
      gap="condensed"
      className={clsx(styles.ModelSelectorConfig, {
        [styles.Disabled]: isDisabled,
      })}
    >
      <span className="sr-only" id={`${id}-label`}>
        {ariaLabel}
      </span>

      <Checkbox
        ref={checkboxRef}
        id={id}
        checked={selected}
        onChange={selectHandler}
        disabled={isDisabled}
        aria-labelledby={`${id}-label`}
      />

      <Stack.Item grow>
        <InlineEdit
          enabled={isEditable}
          onSave={saveHandler}
          defaultValue={displayName}
          returnFocusRef={checkboxRef}
          aria-describedby={`${id}-label`}
        >
          <Stack
            as="label"
            direction="horizontal"
            gap="condensed"
            align="center"
            className="width-full"
            {...{htmlFor: id}}
          >
            <span>{displayName}</span>
            {hasName && <span className="fgColor-muted">{model.slug}</span>}
            {fresh && <Label variant="accent">New</Label>}
            {isDeprecated && <span className={styles.DimLabel}>Deprecated Model</span>}
          </Stack>
        </InlineEdit>
      </Stack.Item>
    </Stack>
  )
}
