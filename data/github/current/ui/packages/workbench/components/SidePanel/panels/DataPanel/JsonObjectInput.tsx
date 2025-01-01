import {useDebounce} from '@github-ui/use-debounce'
import {AlertIcon} from '@primer/octicons-react'
import {FormControl, Textarea} from '@primer/react'
import {useState} from 'react'

import type {JSONValue} from '../../../../utilities/parse-data'
import styles from './JsonObjectInput.module.css'

export interface JsonObjectInputProps {
  value: JSONValue | undefined
  objectKey: string
  readOnly?: boolean
  onChange: (key: string, value: string) => void
}

export const JsonObjectInput = (props: JsonObjectInputProps) => {
  const {value, objectKey, readOnly, onChange} = props
  const [isValidJson, setIsValidJson] = useState(true)

  const verifyJson = useDebounce(() => {
    if (typeof value !== 'string') {
      setIsValidJson(true)
      return
    }

    try {
      JSON.parse(value)
      setIsValidJson(true)
    } catch {
      setIsValidJson(false)
    }
  }, 300)

  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const newValue = e.target.value
    verifyJson()
    onChange(objectKey, newValue)
  }

  return (
    <FormControl key={objectKey} className={styles.container}>
      <FormControl.Label>{objectKey}</FormControl.Label>
      <Textarea
        block
        value={typeof value === 'object' ? JSON.stringify(value, null, 2) : value?.toString()}
        onChange={handleChange}
        rows={5}
        readOnly={readOnly}
        className={styles.jsonTextArea}
      />
      {!isValidJson && (
        <FormControl.Caption className={styles.formatWarning}>
          <AlertIcon size={16} />
          This value is a JSON object. Please ensure it is valid JSON format.
        </FormControl.Caption>
      )}
    </FormControl>
  )
}
