import {useEffect, useState, useCallback, useId} from 'react'
import {Text} from '@primer/react'
import type {ActionProps} from '../ActionProps'
import {SimpleSelect, type Items} from '@github-ui/simple-select'

interface Props extends ActionProps {
  menuButtonPrefix?: string
  title: string
  defaultMenuButtonOption?: string
  menuButtonOptions?: {[key: string]: string}
  menuButtonVariants?: {[key: string]: string}
  listOptions: {[key: string]: string}
  selectedListOptions: string[]
  listVariants?: {[key: string]: string}
  selectedListVariants?: string[]
  width?: 'small' | 'medium'
  onSaveCallback: {(selectedOptions: string[], selectedVariants: string[]): void}
}

function MultipleSelect(props: Props) {
  const {onSaveCallback, selectedListOptions, selectedListVariants, title} = props

  const optionKeys = Object.keys(props.listOptions || {})
  const variantKeys = Object.keys(props.listVariants || {})

  const [selectedOptions, setSelectedOptionsState] = useState<string[]>(selectedListOptions)
  const [selectedVariants, setSelectedVariantsState] = useState<string[]>(selectedListVariants || [])

  useEffect(
    function syncPropsWithState() {
      setSelectedOptionsState(selectedListOptions)
      setSelectedVariantsState(selectedListVariants || [])
    },
    [selectedListOptions, selectedListVariants],
  )

  const onCancel = useCallback(() => {
    setSelectedOptionsState(selectedListOptions)
    setSelectedVariantsState(selectedListVariants || [])
  }, [setSelectedOptionsState, setSelectedVariantsState, selectedListOptions, selectedListVariants])

  const onSave = useCallback(() => {
    onSaveCallback(selectedOptions, selectedVariants)
  }, [onSaveCallback, selectedOptions, selectedVariants])

  const onSelect = useCallback((value: string, list: string[], action: {(selected: string[]): void}) => {
    if (list.includes(value)) {
      action(list.filter(f => f !== value).sort())
    } else {
      action([...list, value])
    }
  }, [])

  const onSelectOption = useCallback(
    (option: string) => {
      onSelect(option, selectedOptions, setSelectedOptionsState)
    },
    [selectedOptions, onSelect],
  )

  const onSelectVariant = useCallback(
    (variant: string) => {
      if (selectedOptions.length !== 0) {
        onSelect(variant, selectedVariants, setSelectedVariantsState)
      }
    },
    [selectedOptions, selectedVariants, onSelect],
  )

  const renderSelected = () => {
    if (selectedListOptions.length === 0) {
      return props.defaultMenuButtonOption
    }
    const renderedOptions = optionKeys.map(value => {
      if (selectedListOptions.includes(value)) {
        return props.menuButtonOptions ? props.menuButtonOptions[value] : props.listOptions[value]
      }
    })
    const prefix = props.menuButtonPrefix || ''
    if (!selectedListVariants || selectedListVariants.length < 1) {
      return (
        <>
          <Text as="span" sx={{color: 'fg.muted'}}>
            {prefix}
          </Text>
          <span>{renderSentence(renderedOptions)}</span>
        </>
      )
    } else {
      const renderedVariants = selectedListVariants?.map(value => {
        return props.menuButtonVariants
          ? props.menuButtonVariants[value]
          : props.listVariants && props.listVariants[value]
      })
      return (
        <>
          <Text as="span" className="hide-sm" sx={{color: 'fg.muted'}}>
            {prefix}
          </Text>
          <span>
            {renderSentence(renderedOptions)}. ({renderSentence(renderedVariants)})
          </span>
        </>
      )
    }
  }

  const renderSentence = (array: Array<string | undefined> | undefined) => {
    if (!array) return
    return array.filter(item => item).join(', ')
  }

  const fallbackButtonId = useId()
  const id = props.id ?? fallbackButtonId
  const buttonProps: ActionProps = {
    id,
    'aria-labelledby': props['aria-labelledby']?.includes(id)
      ? props['aria-labelledby']
      : `${props['aria-labelledby']} ${id}`,
    'aria-describedby': props['aria-describedby'],
  }

  const items = optionKeys.map((option: string) => {
    const label = props.listOptions[option] || ''
    return {
      label,
      id: option,
      selected: selectedOptions.includes(option),
      groupId: 0,
    }
  })

  const variantItems =
    props.listVariants && selectedOptions.length !== 0
      ? variantKeys.map((variant: string) => {
          const label = props.listVariants?.[variant] || ''
          return {
            label,
            id: variant,
            selected: selectedVariants.includes(variant),
            groupId: 1,
          }
        })
      : []

  const availableItems = [...items, ...variantItems]

  const onOptionSelect = (option: Items) => {
    if (variantKeys.includes(option.id)) {
      onSelectVariant(option.id)
      return
    }

    onSelectOption(option.id)
  }

  return (
    <>
      <SimpleSelect
        renderText={renderSelected}
        title={title}
        buttonProps={{size: 'small', ...buttonProps}}
        items={availableItems}
        onSelect={onOptionSelect}
        selectionVariant="multiple"
        onSave={onSave}
        onCancel={onCancel}
        outsideClick="cancel"
        onEscape="cancel"
        focusTarget="first-item"
      />
    </>
  )
}

export default MultipleSelect
