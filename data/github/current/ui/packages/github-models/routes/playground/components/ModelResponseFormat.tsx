import {Button, FormControl, Radio, RadioGroup} from '@primer/react'
import type {PlaygroundResponseFormat} from '../../../types'
import {useCallback, useState} from 'react'
import {JsonSchemaDialog} from './JsonSchemaDialog'
import {testIdProps} from '@github-ui/test-id-props'

import styles from './ModelResponseFormat.module.css'

export function ModelResponseFormat({
  responseFormat,
  handleResponseFormatChange,
  jsonSchema,
  handleJsonSchemaChange,
  supportsJsonSchema,
  onSinglePlaygroundView,
}: {
  responseFormat: PlaygroundResponseFormat
  handleResponseFormatChange: (selectedResponseFormat: PlaygroundResponseFormat) => void
  jsonSchema?: string
  handleJsonSchemaChange: (jsonSchema: string) => void
  supportsJsonSchema: boolean
  onSinglePlaygroundView?: boolean
}) {
  const showJsonSchemaUI = supportsJsonSchema && onSinglePlaygroundView
  const responseFormatIsSchema = responseFormat === 'json_schema'

  const [showDialog, setShowDialog] = useState(false)

  const handleResponseFormatSelection = useCallback(
    (selectedResponseFormat: PlaygroundResponseFormat) => {
      if (selectedResponseFormat === 'json_schema') {
        setShowDialog(true)
      } else {
        setShowDialog(false)
      }

      handleResponseFormatChange(selectedResponseFormat)
    },
    [handleResponseFormatChange],
  )

  const handleSubmitJsonSchemaDialog = useCallback(
    (input: string) => {
      handleJsonSchemaChange(input)
      setShowDialog(false)
    },
    [handleJsonSchemaChange, setShowDialog],
  )

  return (
    <>
      <div {...testIdProps('response-format')}>
        <RadioGroup
          name="Response formats"
          onChange={value => handleResponseFormatSelection(value as PlaygroundResponseFormat)}
        >
          <RadioGroup.Label>Response format</RadioGroup.Label>
          <div className="d-flex gap-3">
            <FormControl>
              <Radio name="text-format" value="text" checked={responseFormat === 'text'} />
              <FormControl.Label>Text</FormControl.Label>
            </FormControl>
            <FormControl>
              <Radio name="json-object-format" value="json_object" checked={responseFormat === 'json_object'} />
              <FormControl.Label>JSON</FormControl.Label>
            </FormControl>
            {showJsonSchemaUI && (
              <div className="d-flex">
                <FormControl>
                  <Radio
                    name="json-schema-format"
                    value="json_schema"
                    checked={responseFormatIsSchema}
                    onClick={() => setShowDialog(true)}
                  />
                  <FormControl.Label>
                    Schema
                    {responseFormatIsSchema && (
                      <Button variant="link" className="color-fg-muted pl-1" onClick={() => setShowDialog(true)}>
                        (edit)
                      </Button>
                    )}
                  </FormControl.Label>
                </FormControl>
              </div>
            )}
          </div>
          <div className={styles.caption}>Set the format for the model response.</div>
        </RadioGroup>
      </div>

      {showJsonSchemaUI && showDialog && (
        <JsonSchemaDialog
          onClose={() => setShowDialog(false)}
          onSubmit={handleSubmitJsonSchemaDialog}
          jsonSchema={jsonSchema}
        />
      )}
    </>
  )
}
