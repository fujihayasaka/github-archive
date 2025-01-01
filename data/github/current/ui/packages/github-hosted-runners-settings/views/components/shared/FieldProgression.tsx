import {useCallback, useState} from 'react'
import FieldProgressionField, {type FieldProgressionFieldProps} from './FieldProgressionField'

type Props = {
  fields: FieldProgressionFieldProps[]
  skipResetFieldOnSave?: boolean
}

export default function FieldProgression({fields, skipResetFieldOnSave}: Props) {
  const [currentFieldIndex, setCurrentFieldIndex] = useState(0)

  const handleSave = useCallback(
    (fieldIndex: number) => {
      // reset subsequent fields
      for (const field of fields.slice(fieldIndex + 1)) {
        field.editComponent.props.setValue(null)
      }
      // move to the next field if there is one, else be done
      setCurrentFieldIndex(fieldIndex + 1)
    },
    [fields],
  )

  const handleSaveWithoutReset = useCallback((fieldIndex: number) => {
    // move to the next field if there is one, else be done
    setCurrentFieldIndex(fieldIndex + 1)
  }, [])

  const setActive = useCallback((fieldIndex: number) => {
    setCurrentFieldIndex(fieldIndex)
  }, [])

  const fieldProgressionFieldsWithIndexesAdded = fields.map((field, index) => {
    const isActive = index === currentFieldIndex
    return (
      <FieldProgressionField
        {...field}
        index={index}
        // eslint-disable-next-line @eslint-react/no-array-index-key
        key={index}
        isActive={isActive}
        onEditClick={() => setActive(index)}
        // we don't want to reset the values if the user is editing a field
        onSave={() => (skipResetFieldOnSave ? handleSaveWithoutReset(index) : handleSave(index))}
      />
    )
  })

  return <>{fieldProgressionFieldsWithIndexesAdded}</>
}
