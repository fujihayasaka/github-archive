import {ActionList, ActionMenu, Checkbox, FormControl, TextInput} from '@primer/react'
import type {ModelInputChangeParams, ModelParameterValue, ModelInputSchemaParameter} from '../../../types'
import {PlaygroundArrayInput} from './PlaygroundArrayInput'
import {PlaygroundNumericInput} from './PlaygroundNumericInput'

export function PlaygroundInput({
  parameter: {key, type, friendlyName, description, required, min, max, options},
  value,
  handleInputChange,
}: {
  parameter: ModelInputSchemaParameter
  value: ModelParameterValue
  handleInputChange: (params: ModelInputChangeParams) => void
}) {
  const onChangeRaw = ({currentTarget}: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    let newValue: ModelParameterValue = currentTarget.value

    if (currentTarget.type === 'checkbox' && currentTarget instanceof HTMLInputElement) {
      newValue = currentTarget.checked as ModelParameterValue
    } else if (type === 'array') {
      newValue = newValue.split('\n')
    }

    handleInputChange({key, value: newValue, validate: false})
  }

  const labelText = friendlyName || key

  if (type === 'string') {
    return (
      <FormControl required={required} id={key}>
        <FormControl.Label>{labelText}</FormControl.Label>
        {description && <FormControl.Caption>{description}</FormControl.Caption>}
        <TextInput type="text" value={value as string} block onChange={onChangeRaw} name={key} />
      </FormControl>
    )
  }

  if (type === 'number' || type === 'integer') {
    return (
      <PlaygroundNumericInput
        description={description}
        name={key}
        label={labelText}
        onChange={onChangeRaw}
        handleInputChange={handleInputChange}
        min={min}
        max={max}
        value={value}
      />
    )
  }

  if (type === 'array') {
    return (
      <PlaygroundArrayInput
        description={description}
        label={labelText}
        name={key}
        value={value}
        onChange={onChangeRaw}
      />
    )
  }

  if (type === 'boolean') {
    return (
      <FormControl id={key}>
        <FormControl.Label>{labelText}</FormControl.Label>
        {description && <FormControl.Caption>{description}</FormControl.Caption>}
        <Checkbox name={key} checked={value as boolean} onChange={onChangeRaw} />
      </FormControl>
    )
  }

  if (type === 'multiple_choice' && Array.isArray(options)) {
    return (
      <FormControl id={key}>
        <FormControl.Label>{labelText}</FormControl.Label>
        {description && <FormControl.Caption>{description}</FormControl.Caption>}

        <ActionMenu>
          <ActionMenu.Button name={key} aria-label={key}>
            {value ? value : 'Select an option'}
          </ActionMenu.Button>
          <ActionMenu.Overlay width="small">
            <ActionList selectionVariant="single">
              {options.map(option => (
                <ActionList.Item
                  key={option}
                  selected={option === value}
                  onSelect={() => handleInputChange({key, value: option, validate: false})}
                >
                  {option}
                </ActionList.Item>
              ))}
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </FormControl>
    )
  }

  return null
}
