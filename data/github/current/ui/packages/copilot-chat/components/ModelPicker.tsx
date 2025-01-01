import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {sendEvent} from '@github-ui/hydro-analytics'
import {CopilotIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ConfirmationDialog, Spinner} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
import {useCallback, useEffect, useState} from 'react'
import {useLocation} from 'react-router-dom'

import type {CopilotChatModel} from '../utils/copilot-chat-types'
import {useChatState, useChatStateLens, useChatStateValues} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {DEFAULT_MODEL} from '../utils/models'

type Command = NewConversationDueToExternalContent | NewConversationDueToDegradedImageSupport | PolicyConfirmation

// This isn't 100% typesafe, but if this pattern continues to extend considering separating out command types into the shape of their actions and reasons as their own enums.
type NewConversationDueToExternalContent = {
  action: 'requires-new-conversation'
  reason: 'external-content'
}
type NewConversationDueToDegradedImageSupport = {
  action: 'requires-new-conversation'
  reason: 'degraded-image-support'
}
type PolicyConfirmation = {
  action: 'requires-policy-approval'
}

interface ModelPickerProps {
  onNewThreadSelected: () => Promise<void>
  limited?: boolean
}

export function ModelPicker({onNewThreadSelected, limited}: ModelPickerProps) {
  const state = useChatState()
  const manager = useChatManager()
  const {model, availableModels} = useChatStateValues('model', 'availableModels')
  const modelsPending = useChatStateLens(s => s.modelsLoading.state === 'pending')
  const {search, pathname} = useLocation()

  const [pending, setPending] = useState<{
    model: CopilotChatModel
    command: Command
  } | null>(null)
  const modelRequiresNewConversationDueToExternalContent =
    useModelSwitchingRequiresNewConversationDueToExternalContent()
  const modelRequiresNewConversationDueToDegradedImageSupport =
    useModelSwitchingRequiresNewConversationDueToDegradedImageSupport()

  const selectedModel = model ?? DEFAULT_MODEL
  const models = availableModels ?? [DEFAULT_MODEL]

  useEffect(() => {
    if (modelsPending) {
      void manager.fetchModels()
    }
  }, [manager, modelsPending])

  // Load model from URL if it exists
  useEffect(() => {
    if (state.mode !== 'immersive') return

    const urlSearchParams = new URLSearchParams(search)
    const queryModel = urlSearchParams.get('model')

    if (queryModel && (pathname === '/copilot' || pathname === '/copilot/')) {
      if (model.id === queryModel) return

      const availableModel = availableModels?.find(m => m.id === queryModel)
      if (availableModel) {
        void manager.selectModel(availableModel, 'url')
        sendEvent('dotcom_chat.activate', {target: 'COPILOT_MODEL_LOADED_FROM_URL', mode: 'immersive'})
      }
    }
    // When the page loads availableModels is empty. Once we fetch the models
    // and availableModels is populated we want this effect to run to update the model.
    // Any other state changes (user picks a different model) should not run this effect again.
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [availableModels])

  // If you don't have at least two models, don't show the picker
  if (models.length < 2) return null

  const onModelPicked = (newModel: CopilotChatModel) => {
    if (newModel.id === selectedModel.id) return
    sendEvent('dotcom_chat.activate', {
      target: 'MODEL_PICKER_MODEL_SELECT',
      mode: 'immersive',
      model: newModel.id,
    })

    if (modelRequiresNewConversationDueToExternalContent(newModel)) {
      setPending({model: newModel, command: {action: 'requires-new-conversation', reason: 'external-content'}})
    } else if (modelRequiresNewConversationDueToDegradedImageSupport(newModel)) {
      setPending({model: newModel, command: {action: 'requires-new-conversation', reason: 'degraded-image-support'}})
    } else if (modelSwitchingRequiresPolicyConfirmation(newModel)) {
      setPending({model: newModel, command: {action: 'requires-policy-approval'}})
    } else {
      void manager.selectModel(newModel)
    }
  }

  return (
    <>
      <ModelPickerDesign
        selectedModel={selectedModel}
        models={models}
        onModelPicked={onModelPicked}
        limited={limited}
      />
      {pending?.command.action === 'requires-new-conversation' && (
        <NewConversationConfirmationDialog
          model={pending.model}
          reason={pending.command.reason}
          onDismiss={() => {
            sendEvent('dotcom_chat.activate', {
              target: 'MODEL_PICKER_DIALOG_REQUIRES_NEW_CONVERSATION_CANCEL',
              mode: 'immersive',
              model: pending.model.id,
            })
            setPending(null)
          }}
          onSwitch={async () => {
            sendEvent('dotcom_chat.activate', {
              target: 'MODEL_PICKER_DIALOG_REQUIRES_NEW_CONVERSATION_CONFIRM',
              mode: 'immersive',
              model: pending.model.id,
            })
            setPending(null)
            await onNewThreadSelected()
            void manager.selectModel(pending.model)
          }}
        />
      )}
      {pending?.command.action === 'requires-policy-approval' && (
        <ModelPolicyConfirmationDialog
          model={pending.model}
          onDismiss={() => {
            sendEvent('dotcom_chat.activate', {
              target: 'MODEL_PICKER_DIALOG_POLICY_CANCEL',
              mode: 'immersive',
              model: pending.model.id,
            })
            setPending(null)
          }}
          onConfirm={async () => {
            await manager.acceptModelPolicy(pending.model)
            void manager.selectModel(pending.model)
            sendEvent('dotcom_chat.activate', {
              target: 'MODEL_PICKER_DIALOG_POLICY_CONFIRM',
              mode: 'immersive',
              model: pending.model.id,
            })
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
  limited?: boolean
}

function ModelPickerDesign({selectedModel, models, onModelPicked, limited}: ModelPickerDesignProps) {
  const baseModels = models.filter(m => !m.preview)
  const previewModels = models.filter(m => m.preview)
  const uniqueVendors = new Set(models.map(m => m.vendor))
  const hasMultipleVendors = uniqueVendors.size > 1
  const hasThirdPartyModel = models.some(m => m.isThirdParty)

  // Only if limited is true, we include these "upsell" models.
  const upsellModelsToDisplay = limited ? upsellModels : []

  const handleMenuOpen = useCallback(() => {
    sendEvent('dotcom_chat.activate', {
      target: 'MODEL_PICKER_OPEN',
      mode: 'immersive',
      model: selectedModel.id,
    })
  }, [selectedModel.id])

  return (
    <ActionMenu>
      <ActionMenu.Button variant="invisible" onClick={handleMenuOpen}>
        <span className="sr-only">Model: </span>
        {selectedModel.displayName}
      </ActionMenu.Button>
      <ActionMenu.Overlay sx={{width: 'var(--overlay-width-small)'}} align="center">
        <ActionList selectionVariant="single">
          {baseModels.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading>Models</ActionList.GroupHeading>
              {baseModels.map(m => (
                <ModelListItem
                  key={m.id}
                  model={m}
                  selected={m.id === selectedModel.id}
                  onModelPicked={onModelPicked}
                  hasMultipleVendors={hasMultipleVendors}
                  hasThirdPartyModel={hasThirdPartyModel}
                />
              ))}
            </ActionList.Group>
          )}

          {(previewModels.length > 0 || upsellModelsToDisplay.length > 0) && (
            <ActionList.Group>
              <ActionList.GroupHeading>Preview</ActionList.GroupHeading>

              {previewModels.map(m => (
                <ModelListItem
                  key={m.id}
                  model={m}
                  selected={m.id === selectedModel.id}
                  onModelPicked={onModelPicked}
                  hasMultipleVendors={hasMultipleVendors}
                  hasThirdPartyModel={hasThirdPartyModel}
                />
              ))}

              {upsellModelsToDisplay.map(m => (
                <ActionList.LinkItem key={m.id} href={upsellURL}>
                  <ActionList.LeadingVisual>
                    <ModelVendorIcon model={m} />
                  </ActionList.LeadingVisual>
                  {m.displayName}
                  <ActionList.Description variant="block" truncate>
                    {m.vendor}
                  </ActionList.Description>
                  <ActionList.TrailingVisual>
                    <div className="fgColor-muted">Upgrade</div>
                  </ActionList.TrailingVisual>
                </ActionList.LinkItem>
              ))}
            </ActionList.Group>
          )}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

interface ModelListItemProps {
  model: CopilotChatModel
  selected: boolean
  onModelPicked: (m: CopilotChatModel) => void
  hasMultipleVendors: boolean
  hasThirdPartyModel: boolean
}

function ModelListItem({model, selected, onModelPicked, hasMultipleVendors, hasThirdPartyModel}: ModelListItemProps) {
  return (
    <ActionList.Item key={model.id} onSelect={() => onModelPicked(model)} selected={selected}>
      {(hasMultipleVendors || hasThirdPartyModel) && (
        <ActionList.LeadingVisual>
          <ModelVendorIcon model={model} />
        </ActionList.LeadingVisual>
      )}
      {model.displayName}
      {(hasMultipleVendors || hasThirdPartyModel) && (
        <ActionList.Description variant="block" truncate>
          {model.vendor}
        </ActionList.Description>
      )}
    </ActionList.Item>
  )
}

function NewConversationConfirmationDialog({
  model,
  onDismiss,
  onSwitch,
  reason,
}: {
  model: CopilotChatModel
  onDismiss: () => void
  onSwitch: () => void
  reason: string
}) {
  return (
    <ConfirmationDialog
      title="Switch model"
      onClose={gesture => (gesture === 'confirm' ? onSwitch() : onDismiss())}
      confirmButtonContent="New conversation"
      confirmButtonType="primary"
    >
      {reason === 'external-content' && (
        <p>
          The {model.displayName} model currently doesn’t support external context from ongoing conversations. Start a
          new conversation to chat with this model.
        </p>
      )}
      {reason === 'degraded-image-support' && (
        <p>
          The {model.displayName} model doesn’t support answering questions about images. Start a new conversation
          without images to chat with this model.
        </p>
      )}
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

function ModelVendorIcon({model}: {model: Pick<CopilotChatModel, 'vendor' | 'logoURL'>}) {
  return model.logoURL ? (
    <GitHubAvatar alt={`${model.vendor} logo`} square size={18} src={model.logoURL} />
  ) : (
    <CopilotIcon />
  )
}

function useModelSwitchingRequiresNewConversationDueToExternalContent(): (m: CopilotChatModel) => boolean {
  const hasFunctionCalls = useChatStateLens(s => s.messages.some(m => m.skillExecutions?.length))

  return useCallback(
    (m: CopilotChatModel) =>
      hasFunctionCalls &&
      (!m.capabilities.supports.tool_calls ||
        m.isThirdParty ||
        // TODO: temporary - o1-ga supports tool calling, but the dotcom chat code in CAPI currently does not
        // As of 2024-12-17 we expect this to be done in a few business days
        m.capabilities.family === 'o1-ga'),
    [hasFunctionCalls],
  )
}

function useModelSwitchingRequiresNewConversationDueToDegradedImageSupport(): (m: CopilotChatModel) => boolean {
  const hasMediaContent = useChatStateLens(
    s => s.messages.some(m => m.mediaContent?.length) || s.currentReferences.some(cr => cr.type === 'image'),
  )

  return useCallback((m: CopilotChatModel) => hasMediaContent && !m.capabilities.supports.vision, [hasMediaContent])
}

function modelSwitchingRequiresPolicyConfirmation(m: CopilotChatModel): boolean {
  return !!m.policy && m.policy.state !== 'enabled'
}

const upsellURL = 'https://github.com/features/copilot#pricing'

// TODO: We are hard-coding these until CAPI supports returning models the user does not currently have access to.
// This work should be done by February 2025. If this code still exists after that, something has changed.
const upsellModels: Array<Pick<CopilotChatModel, 'logoURL' | 'displayName' | 'vendor' | 'id'>> = [
  {
    id: 'claude-3.7-sonnet-upgrade',
    displayName: 'Claude 3.7 Sonnet',
    vendor: 'Anthropic',
    logoURL: '/images/modules/marketplace/models/families/anthropic.svg',
  },
  {
    id: 'o1-upgrade',
    displayName: 'o1',
    vendor: 'Azure OpenAI',
    logoURL: '/images/modules/marketplace/models/families/openai.svg',
  },
]
