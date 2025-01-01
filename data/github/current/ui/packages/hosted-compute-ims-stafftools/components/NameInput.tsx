import {FormControl, TextInput} from '@primer/react'
import {validateImageDefinitionName} from '../helpers/utils'
import {useState} from 'react'
import {Constants} from '../helpers/constants'

interface NameInputProps {
  name: string
  onNameChange: (name: string) => void
}

export function NameInput({name, onNameChange}: NameInputProps) {
  const [isNameValid, setIsNameValid] = useState(true)
  const handleNameChange = (value: string) => {
    setIsNameValid(validateImageDefinitionName(value))
    onNameChange(value)
  }
  return (
    <FormControl required>
      <FormControl.Label>Name</FormControl.Label>
      <TextInput name="name" value={name} onChange={e => handleNameChange(e.target.value)} />
      {!isNameValid && <FormControl.Validation variant="error">{Constants.nameValidation}</FormControl.Validation>}
    </FormControl>
  )
}
