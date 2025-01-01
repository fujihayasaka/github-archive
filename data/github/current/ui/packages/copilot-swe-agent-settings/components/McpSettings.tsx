import {Button, FormControl} from '@primer/react'
import {McpSettingsEditor} from './McpSettingsEditor'
import {Stack} from './Ui'
import {useSweAgentSettingsMutation} from '../hooks/useSweAgentSettingsMutation'

export function McpSettings({endpoint, initialValue}: {endpoint: string; initialValue: string}) {
  const {value, fieldStatus, onChange, onSave} = useSweAgentSettingsMutation(endpoint, initialValue)

  return (
    <>
      <Stack space="spacious">
        <FormControl>
          <FormControl.Label>MCP configuration</FormControl.Label>
          {fieldStatus ? (
            <FormControl.Validation variant={fieldStatus.status}>{fieldStatus.message}</FormControl.Validation>
          ) : (
            <FormControl.Caption>Your configuration will be validated on save.</FormControl.Caption>
          )}
          <McpSettingsEditor
            labelId="editorLabeledById"
            value={value}
            onChange={onChange}
            fieldStatus={fieldStatus?.status}
            placeholder={`{\n  "mcpServers": {}\n}`}
          />
        </FormControl>
        <Button variant="default" onClick={onSave}>
          Save
        </Button>
      </Stack>
    </>
  )
}
