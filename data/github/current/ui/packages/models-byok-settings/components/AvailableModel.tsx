import {AiModelIcon, AlertFillIcon, CopilotIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Label, Stack} from '@primer/react'
import {type SyntheticEvent, useCallback, useId, useState} from 'react'

import {getErrorMessageFromResponse} from '../helpers/extract-errors'
import type {UpdateCustomModelPayload} from '../routes/CustomModelsIndex/use-update-custom-model'
import type {CustomKey, CustomModel} from '../types'

interface AvailableModelProps {
  customKey: CustomKey
  model: CustomModel
  updateModel: (update: UpdateCustomModelPayload) => Promise<void>
}

export function AvailableModel({customKey, model, updateModel}: AvailableModelProps) {
  const id = useId()

  return (
    <Stack.Item grow className="Box-row--hover-gray d-flex gap-2 p-3 border-bottom flex-items-center">
      <AiModelIcon size="small" />
      <div className="text-bold" id={id}>
        {model.name ?? model.slug}
      </div>
      <div className="flex-1 pt-1 text-small fgColor-muted">{customKey.name}</div>
      <ActionMenu>
        <ActionMenu.Button count={getEnabledCount(model)} aria-describedby={id}>
          Enabled
        </ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList selectionVariant="multiple">
            <ActionList.GroupHeading>Features this model is enabled for</ActionList.GroupHeading>
            <CopilotItem model={model} updateModel={updateModel} />
            <GitHubModelsItem selected={model.enabled.models} />
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </Stack.Item>
  )
}

function CopilotItem({
  model,
  updateModel,
}: {
  model: CustomModel
  updateModel: (update: UpdateCustomModelPayload) => Promise<void>
}) {
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const onSelect = useCallback(
    async (event: SyntheticEvent) => {
      event.preventDefault()

      // We don't have the luxury of useMutation here yet, so we handle loading/errors manually
      // See comment in useUpdateCustomModel (ui/packages/models-byok-settings/hooks/use-update-custom-model.ts)
      try {
        setBusy(true)
        await updateModel({modelId: model.id, copilotChatEnabled: !model.enabled.copilot})
        setError(null)
      } catch (ex) {
        const maybeError = await getErrorMessageFromResponse(ex)
        setError(maybeError || 'Failed to update')
      } finally {
        setBusy(false)
      }
    },
    [model, updateModel],
  )

  return (
    <ActionList.Item selected={model.enabled.copilot} onSelect={onSelect} loading={busy}>
      <ActionList.LeadingVisual>
        <CopilotIcon size="small" />
      </ActionList.LeadingVisual>
      GitHub Copilot
      <ActionList.Description variant="block">
        Copilot in VSCode and Web
        {error && (
          <p className="fgColor-danger mt-1">
            <AlertFillIcon size="small" className="fgColor-danger mr-1" />
            Error: {error}
          </p>
        )}
      </ActionList.Description>
    </ActionList.Item>
  )
}

function GitHubModelsItem({selected}: {selected: boolean}) {
  return (
    <ActionList.Item
      selected={selected}
      inactiveText="Change this setting by going to Models &gt; Development &gt; Permissions"
    >
      <ActionList.LeadingVisual>
        <AiModelIcon size="small" />
      </ActionList.LeadingVisual>
      GitHub Models <Label variant="success">Preview</Label>
    </ActionList.Item>
  )
}

const getEnabledCount = ({enabled: {models, copilot}}: CustomModel) => (models ? 1 : 0) + (copilot ? 1 : 0)
