import {Checkbox, FormControl, TextInput, Textarea} from '@primer/react'
import type {ModelInputChangeParams, ModelParameterValue, ModelInputSchemaParameter} from '../../../types'
import {useRef} from 'react'

import styles from '../../../models.module.css'

export function PlaygroundInput({
  parameter: {key, type, friendlyName, description, required, min, max},
  value,
  handleInputChange,
}: {
  parameter: ModelInputSchemaParameter
  value: ModelParameterValue
  handleInputChange: (params: ModelInputChangeParams) => void
}) {
  const textAreaRef = useRef<HTMLTextAreaElement>(null)
  const showSlider = max !== undefined && min !== undefined

  const onChangeRaw = ({currentTarget}: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    let newValue: ModelParameterValue = currentTarget.value

    if (currentTarget.type === 'checkbox' && currentTarget instanceof HTMLInputElement) {
      newValue = currentTarget.checked as ModelParameterValue
    } else if (type === 'array') {
      newValue = newValue.split('\n')
    }

    handleInputChange({key, value: newValue, validate: false})
  }

  const onChangeValidated = (newValue: ModelParameterValue) => handleInputChange({key, value: newValue, validate: true})

  const renderInput = (): JSX.Element | null => {
    switch (type) {
      case 'string':
        return <TextInput type="text" value={value as string} block onChange={onChangeRaw} name={key} />
      case 'number':
      case 'integer':
        return (
          <div className="width-full d-flex gap-3 flex-items-center">
            <TextInput
              name={key}
              id={key}
              type="number"
              max={max}
              min={min}
              step={max === 1 ? 0.01 : 1}
              value={value as string}
              block
              onChange={onChangeRaw}
              onBlur={() => onChangeValidated(value)}
              sx={{width: '30%'}}
            />
            {}
            {showSlider && (
              <>
                <input
                  id={`${key}-range-input`}
                  name={`${key}-range-input`}
                  type="range"
                  value={value as number}
                  min={min}
                  max={max}
                  step={max === 1 ? 0.01 : 1}
                  onChange={({currentTarget}) => onChangeValidated(currentTarget.value)}
                  className={`flex-1 ${styles['range-input']}`}
                  aria-labelledby={`${key}-range-input-label`}
                />
                <label id={`${key}-range-input-label`} htmlFor={`${key}-range-input`} className="sr-only">
                  {friendlyName}
                </label>
              </>
            )}
          </div>
        )

      case 'array':
        return (
          <Textarea
            ref={textAreaRef}
            name={key}
            value={typeof value === 'string' ? value : (value as string[]).join('\n')} // some models have this as an array, others have it as a string
            block
            rows={1}
            resize="vertical"
            onChange={onChangeRaw}
          />
        )
      case 'boolean':
        return <Checkbox name={key} checked={value as boolean} onChange={onChangeRaw} />
    }
  }

  return (
    <FormControl key={key} required={type === 'string' && required} id={key}>
      <FormControl.Label htmlFor={key}>{friendlyName || key}</FormControl.Label>
      {description && <FormControl.Caption>{description}</FormControl.Caption>}
      {renderInput()}
    </FormControl>
  )
}
