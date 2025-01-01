import {FormControl, TextInput} from '@primer/react'
import {validateImageDefinitionName} from '../helpers/utils'
import {useState} from 'react'

interface ImageDefinitionNameInputProps {
  name: string
  onNameChange: (name: string) => void
}

export function ImageDefinitionNameInput({name, onNameChange}: ImageDefinitionNameInputProps) {
  const [isNameValid, setIsNameValid] = useState(true)
  const handleNameChange = (value: string) => {
    setIsNameValid(validateImageDefinitionName(value))
    onNameChange(value)
  }
  return (
    <FormControl required>
      <FormControl.Label>Name</FormControl.Label>
      <TextInput name="name" block value={name} onChange={e => handleNameChange(e.target.value)} />
      {!isNameValid && (
        <FormControl.Validation variant="error">
          Must be 1-100 characters, and may only contain letters, numbers, spaces, parentheses, periods (.), hyphens
          (-), and underscores (_).
        </FormControl.Validation>
      )}
    </FormControl>
  )
}
