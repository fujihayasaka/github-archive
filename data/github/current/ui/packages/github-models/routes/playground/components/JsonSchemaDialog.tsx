import {FormControl, Link} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
import React, {type FormEvent, lazy, useState} from 'react'
import {isValidJSONSchema, sampleJsonSchemaString} from './json-schema-utils'
import {JSON_SCHEMA_DOCS_URL} from './constants'
import styles from './JsonSchemaDialog.module.css'

const CodeMirror = lazy(() => import('@github-ui/code-mirror'))

export function JsonSchemaDialog({
  onClose,
  onSubmit,
  jsonSchema,
}: {
  onClose: () => void
  onSubmit: (input: string) => void
  jsonSchema?: string
}) {
  const [isValidJSON, setIsValidJSON] = useState(true)
  const [jsonInput, setJsonInput] = useState(jsonSchema || '')

  const validateForm = async (event: FormEvent) => {
    event.preventDefault()

    if (!isValidJSONSchema(jsonInput)) {
      setIsValidJSON(false)
      return
    }

    onSubmit(jsonInput)
  }

  const handleChange = (input: string) => {
    setJsonInput(input)
  }

  return (
    <Dialog
      title="JSON Schema"
      subtitle={
        <>
          Provide{' '}
          <Link href={JSON_SCHEMA_DOCS_URL} inline target="_blank" rel="noopener noreferrer">
            JSON schema
          </Link>{' '}
          to define the structure of the model&apos;s output.
        </>
      }
      width="xlarge"
      className={styles.dialog}
      onClose={onClose}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
          form: 'json-schema-form',
        },
        {
          buttonType: 'primary',
          content: 'Save',
          onClick: validateForm,
          form: 'json-schema-form',
        },
      ]}
    >
      {!isValidJSON ? (
        <Banner
          variant="critical"
          className="mb-2"
          title="Error"
          hideTitle
          description="Invalid JSON schema provided. Please verify the required schema structure and fields."
        />
      ) : jsonInput?.trim() === '' ? (
        <Banner
          className="mb-2"
          title="Info"
          hideTitle
          description="No JSON schema saved. Valid schema required for playground."
          primaryAction={
            <Banner.PrimaryAction onClick={() => handleChange(sampleJsonSchemaString)}>Use sample</Banner.PrimaryAction>
          }
        />
      ) : null}
      <FormControl>
        <FormControl.Label>Definition</FormControl.Label>
        <React.Suspense fallback={<></>}>
          <CodeMirror
            fileName="document.json"
            value={jsonInput}
            placeholder={sampleJsonSchemaString}
            ariaLabelledBy="json-schema-code-label"
            minHeight="300px"
            spacing={{
              indentUnit: 2,
              indentWithTabs: false,
              lineWrapping: true,
            }}
            hideHelpUntilFocus
            onChange={handleChange}
            isReadOnly={false}
          />
        </React.Suspense>
      </FormControl>
    </Dialog>
  )
}
