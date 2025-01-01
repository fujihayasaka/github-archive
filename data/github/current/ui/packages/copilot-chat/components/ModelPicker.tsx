import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {CopilotIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ConfirmationDialog, Label, Spinner} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
import {useCallback, useEffect, useState} from 'react'

import type {CopilotChatModel} from '../utils/copilot-chat-types'
import {useChatStateLens, useChatStateValues} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {DEFAULT_MODEL} from '../utils/models'

type PendingReason = 'requires-new-conversation' | 'requires-policy-approval'

export function ModelPicker() {
  const manager = useChatManager()
  const {model, availableModels} = useChatStateValues('model', 'availableModels')
  const modelsPending = useChatStateLens(s => s.modelsLoading.state === 'pending')

  const [pending, setPending] = useState<{model: CopilotChatModel; reason: PendingReason} | null>(null)
  const modelRequiresNewConversation = useModelSwitchingRequiresNewConversation()

  useEffect(() => {
    if (modelsPending) {
      void manager.fetchModels()
    }
  }, [manager, modelsPending])

  const selectedModel = model ?? DEFAULT_MODEL
  const models = availableModels ?? [DEFAULT_MODEL]

  // If you don't have at least two models, don't show the picker
  if (models.length < 2) return null

  const onModelPicked = (newModel: CopilotChatModel) => {
    if (newModel.id === selectedModel.id) return

    if (modelRequiresNewConversation(newModel)) {
      setPending({model: newModel, reason: 'requires-new-conversation'})
    } else if (modelSwitchingRequiresPolicyConfirmation(newModel)) {
      setPending({model: newModel, reason: 'requires-policy-approval'})
    } else {
      void manager.selectModel(newModel)
    }
  }

  return (
    <>
      <ModelPickerDesign selectedModel={selectedModel} models={models} onModelPicked={onModelPicked} />
      {pending?.reason === 'requires-new-conversation' && (
        <NewConversationConfirmationDialog
          model={pending.model}
          onDismiss={() => setPending(null)}
          onSwitch={async () => {
            await manager.selectThread(null)
            void manager.selectModel(pending.model)
            setPending(null)
          }}
        />
      )}
      {pending?.reason === 'requires-policy-approval' && (
        <ModelPolicyConfirmationDialog
          model={pending.model}
          onDismiss={() => setPending(null)}
          onConfirm={async () => {
            await manager.acceptModelPolicy(pending.model)
            void manager.selectModel(pending.model)
            setPending(null)
          }}
        />
      )}
    </>
  )
}

interface ModelPickerDesignProps {
  selectedModel: CopilotChatModel
  models: CopilotChatModel[]
  onModelPicked: (m: CopilotChatModel) => void
}

function ModelPickerDesign({selectedModel, models, onModelPicked}: ModelPickerDesignProps) {
  const baseModels = models.filter(m => !m.preview)
  const previewModels = models.filter(m => m.preview)
  const uniqueVendors = new Set(models.map(m => m.vendor))
  const hasMultipleVendors = uniqueVendors.size > 1
  const hasThirdPartyModel = models.some(m => m.isThirdParty)
  // xsmall is 12rem, which is not enough for our model name text. This width was specifically chosen to fit the model names
  const overlayWidth = hasThirdPartyModel ? 'var(--overlay-width-small)' : '13rem'

  if (!hasThirdPartyModel) {
    return (
      <ActionMenu>
        <ActionMenu.Button variant="invisible">{selectedModel.displayName}</ActionMenu.Button>
        <ActionMenu.Overlay sx={{width: overlayWidth}} align="center">
          <ActionList selectionVariant="single">
            <ActionList.Group>
              <ActionList.GroupHeading>Models</ActionList.GroupHeading>
              {models.map(m => (
                <ActionList.Item key={m.id} onSelect={() => onModelPicked(m)} selected={m.id === selectedModel.id}>
                  {m.displayName}
                  {m.preview && (
                    <ActionList.TrailingVisual>
                      <Label variant="success">Preview</Label>
                    </ActionList.TrailingVisual>
                  )}
                </ActionList.Item>
              ))}
            </ActionList.Group>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    )
  }
  return (
    <ActionMenu>
      <ActionMenu.Button variant="invisible">{selectedModel.displayName}</ActionMenu.Button>
      <ActionMenu.Overlay sx={{width: overlayWidth}} align="center">
        <ActionList selectionVariant="single">
          {baseModels.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading>Models</ActionList.GroupHeading>
              {baseModels.map(m => (
                <ActionList.Item key={m.id} onSelect={() => onModelPicked(m)} selected={m.id === selectedModel.id}>
                  {(hasMultipleVendors || hasThirdPartyModel) && (
                    <ActionList.LeadingVisual>
                      <ModelVendorIcon model={m} />
                    </ActionList.LeadingVisual>
                  )}
                  {m.displayName}
                  {(hasMultipleVendors || hasThirdPartyModel) && (
                    <ActionList.Description>{m.vendor}</ActionList.Description>
                  )}
                </ActionList.Item>
              ))}
            </ActionList.Group>
          )}
          {previewModels.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading>
                <div className="d-flex flex-items-center" style={{gap: '0.5rem'}}>
                  <span>Additional models</span>
                  <Label variant="success">Preview</Label>
                </div>
              </ActionList.GroupHeading>

              {previewModels.map(m => (
                <ActionList.Item key={m.id} onSelect={() => onModelPicked(m)} selected={m.id === selectedModel.id}>
                  {(hasMultipleVendors || hasThirdPartyModel) && (
                    <ActionList.LeadingVisual>
                      <ModelVendorIcon model={m} />
                    </ActionList.LeadingVisual>
                  )}
                  {m.displayName}
                  {(hasMultipleVendors || hasThirdPartyModel) && (
                    <ActionList.Description>{m.vendor}</ActionList.Description>
                  )}
                </ActionList.Item>
              ))}
            </ActionList.Group>
          )}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

function NewConversationConfirmationDialog({
  model,
  onDismiss,
  onSwitch,
}: {
  model: CopilotChatModel
  onDismiss: () => void
  onSwitch: () => void
}) {
  return (
    <ConfirmationDialog
      title="Switch model"
      onClose={gesture => (gesture === 'confirm' ? onSwitch() : onDismiss())}
      confirmButtonContent="New conversation"
      confirmButtonType="primary"
    >
      The {model.displayName} model currently doesn’t support external context from ongoing conversations. Start a new
      conversation to chat with this model.
    </ConfirmationDialog>
  )
}

function ModelPolicyConfirmationDialog({
  model,
  onDismiss,
  onConfirm,
}: {
  model: CopilotChatModel
  onDismiss: () => void
  onConfirm: () => Promise<void>
}) {
  const [error, setError] = useState<string | null>(null)
  const [updating, setUpdating] = useState(false)
  // We should only render this component for a model with an unaccepted policy,
  // which means we should have terms. The fallback is purely defensive.
  const messageMarkdown = model.policy?.terms ?? ''

  const handleConfirm = async () => {
    try {
      setUpdating(true)
      await onConfirm()
      setError(null)
    } catch {
      setError('An error occurred while updating the policy')
    } finally {
      setUpdating(false)
    }
  }
  return (
    <Dialog
      width="large"
      onClose={onDismiss}
      title={`Enable ${model.displayName}`}
      footerButtons={[
        {buttonType: 'default', content: 'Cancel', onClick: onDismiss},
        {
          buttonType: 'primary',
          content: updating ? <Spinner sx={{mx: 2}} size="small" /> : 'Enable',
          onClick: () => void handleConfirm(),
        },
      ]}
    >
      {error && (
        <Banner title="Error" variant="critical">
          {error}
        </Banner>
      )}
      <MarkdownRenderer markdown={messageMarkdown} />
    </Dialog>
  )
}

function ModelVendorIcon({model}: {model: CopilotChatModel}) {
  return model.logoURL ? (
    <GitHubAvatar alt={`${model.vendor} logo`} square size={18} src={model.logoURL} />
  ) : (
    <CopilotIcon />
  )
}

function useModelSwitchingRequiresNewConversation(): (m: CopilotChatModel) => boolean {
  const hasFunctionCalls = useChatStateLens(s => s.messages.some(m => m.skillExecutions?.length))

  return useCallback(
    (m: CopilotChatModel) => hasFunctionCalls && (!m.capabilities.supports.tool_calls || m.isThirdParty),
    [hasFunctionCalls],
  )
}

function modelSwitchingRequiresPolicyConfirmation(m: CopilotChatModel): boolean {
  return !!m.policy && m.policy.state !== 'enabled'
}
