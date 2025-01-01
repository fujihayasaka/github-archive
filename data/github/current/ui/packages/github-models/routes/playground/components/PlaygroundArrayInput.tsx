import {type ChangeEventHandler, useRef} from 'react'
import {FormControl, Textarea} from '@primer/react'
import type {ModelParameterValue} from '../../../types'

interface PlaygroundArrayInputProps {
  name: string
  label?: string | undefined
  description?: string | undefined
  onChange: ChangeEventHandler<HTMLTextAreaElement>
  value: ModelParameterValue
}

export function PlaygroundArrayInput({name, description, label, onChange, value}: PlaygroundArrayInputProps) {
  const textAreaRef = useRef<HTMLTextAreaElement>(null)

  return (
    <FormControl id={name}>
      <FormControl.Label>{label ?? name}</FormControl.Label>
      {description && <FormControl.Caption>{description}</FormControl.Caption>}
      <Textarea
        ref={textAreaRef}
        name={name}
        value={typeof value === 'string' ? value : (value as string[]).join('\n')} // some models have this as an array, others have it as a string
        block
        rows={1}
        resize="vertical"
        onChange={onChange}
      />
    </FormControl>
  )
}
