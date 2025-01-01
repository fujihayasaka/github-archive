import {useCallback} from 'react'
import {Checkbox, CheckboxGroup, FormControl} from '@primer/react'
import type {ForkDestination, FieldComponentProps} from '../../types'
import {useFormField} from '../../hooks/use-form-field'

// eslint-disable-next-line @eslint-react/no-unstable-default-props
export function ForkDestinationsField({initialValue = []}: FieldComponentProps<ForkDestination[]>) {
  const field = useFormField('forkDestination', initialValue)
  const toggleDestination = useCallback(
    (destination: ForkDestination, checked: boolean) => {
      const destinationIsChecked = field.value.includes(destination)
      if (checked) {
        if (!destinationIsChecked) {
          field.update([...field.value, destination])
        }
      } else {
        if (destinationIsChecked) {
          field.update(field.value.filter(dest => dest !== destination))
        }
      }
    },
    [field],
  )

  return (
    <CheckboxGroup>
      <CheckboxGroup.Label>Fork destinations</CheckboxGroup.Label>
      <FormControl>
        <Checkbox
          checked={field.value.includes('EXTERNAL')}
          onChange={e => toggleDestination('EXTERNAL', e.target.checked)}
        />
        <FormControl.Label>This organization</FormControl.Label>
        <FormControl.Caption>
          Forks of repositories in this group can be created within this organization.
        </FormControl.Caption>
      </FormControl>
      <FormControl>
        <Checkbox
          checked={field.value.includes('INTERNAL')}
          onChange={e => toggleDestination('INTERNAL', e.target.checked)}
        />
        <FormControl.Label>Other enterprise organizations</FormControl.Label>
        <FormControl.Caption>
          Forks of repositories in this group can be created within other enterprise organizations.
        </FormControl.Caption>
      </FormControl>
      <FormControl>
        <Checkbox
          checked={field.value.includes('USERS')}
          onChange={e => toggleDestination('USERS', e.target.checked)}
        />
        <FormControl.Label>User accounts</FormControl.Label>
        <FormControl.Caption>
          Forks of repositories in this group can be created within user accounts.
        </FormControl.Caption>
      </FormControl>
    </CheckboxGroup>
  )
}
