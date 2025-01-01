import {FormControl, TextInput} from '@primer/react'
import type {ModelInputChangeParams, ModelParameterValue} from '../../../types'
import type {ChangeEventHandler} from 'react'
import styles from './PlaygroundNumericInput.module.css'

interface PlaygroundNumericInputProps {
  name: string
  label?: string | undefined
  description?: string | undefined
  min?: number | undefined
  max?: number | undefined
  value: ModelParameterValue
  onChange: ChangeEventHandler<HTMLInputElement>
  handleInputChange: (params: ModelInputChangeParams) => void
}

export function PlaygroundNumericInput({
  handleInputChange,
  name,
  label,
  description,
  min,
  max,
  onChange,
  value,
}: PlaygroundNumericInputProps) {
  const showSlider = max !== undefined && min !== undefined
  const onChangeValidated = (newValue: ModelParameterValue) =>
    handleInputChange({key: name, value: newValue, validate: true})
  const descriptionId = description ? `${name}-description` : undefined

  return (
    <div>
      <div className="width-full d-flex gap-3 flex-items-end">
        <FormControl className={styles['number-control']} id={name}>
          <FormControl.Label>{label ?? name}</FormControl.Label>
          <TextInput
            name={name}
            type="number"
            max={max}
            min={min}
            step={max === 1 ? 0.01 : 1}
            value={value as string}
            block
            onChange={onChange}
            onBlur={() => onChangeValidated(value)}
            aria-describedby={descriptionId}
          />
        </FormControl>
        {showSlider && (
          <FormControl id={`${name}-range-input`} className="width-full">
            <FormControl.Label visuallyHidden>{label ?? name} slider</FormControl.Label>
            <TextInput
              name={`${name}-range-input`}
              type="range"
              value={value as number}
              min={min}
              max={max}
              step={max === 1 ? 0.01 : 1}
              onChange={({currentTarget}) => onChangeValidated(currentTarget.value)}
              className={`flex-1 ${styles['range-input']}`}
            />
          </FormControl>
        )}
      </div>
      {description && (
        <div className={styles['field-description']} id={descriptionId}>
          {description}
        </div>
      )}
    </div>
  )
}
