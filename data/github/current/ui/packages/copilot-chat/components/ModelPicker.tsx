import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {sendEvent} from '@github-ui/hydro-analytics'
import {CopilotIcon, LockIcon, SyncIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ButtonGroup, ConfirmationDialog, IconButton, Link, Spinner} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
import {useCallback, useEffect, useRef, useState} from 'react'
import {useLocation} from 'react-router-dom'

import {
  ENABLE_ADDITIONAL_REQUESTS_URL,
  FREE_QUOTA_TRIGGER,
  MANAGE_BILLING_URL,
  PREMIUM_QUOTA_TRIGGER,
  UPGRADE_PLAN_URL,
  UPGRADE_TO_PRO_PLAN_URL,
} from '../utils/copilot-chat-helpers'
import {getActiveMessages} from '../utils/copilot-chat-subthreading-helpers'
import {
  type CopilotChatMessage,
  type CopilotChatModel,
  type CopilotChatReference,
  CopilotPlan,
} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {BASE_MODEL_ID, getDefaultModel} from '../utils/models'
import styles from './ModelPicker.module.css'
import {useEntitlement} from './quota/EntitlementContext'

type ModelPickerType = 'global' | 'message-retry'
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
  type?: ModelPickerType
  selectedModel?: CopilotChatModel // defaults to the thread's model if unset
  onModelSelected?: (model: CopilotChatModel) => void
  disabled?: boolean
}

export function ModelPicker({
  onNewThreadSelected,
  limited,
  type = 'global',
  selectedModel,
  onModelSelected,
  disabled = false,
}: ModelPickerProps) {
  const manager = useChatManager()
  const {model, availableModels, mode, messages, currentReferences, selectedThreadID, modelsLoading} = useChatState()
  const {premiumInteractionsQuotaExceeded, overagesEnabled, plan} = useEntitlement()
  const modelsPending = modelsLoading.state === 'pending'
  const {search, pathname} = useLocation()
  const hasSelectedDefaultModel = useRef(false)

  const shouldShowFallbackModel =
    copilotFeatureFlags.premiumRequestQuotasEnabled && premiumInteractionsQuotaExceeded && !overagesEnabled

  const [pending, setPending] = useState<{
    model: CopilotChatModel
    command: Command
  } | null>(null)

  if (!selectedModel) {
    selectedModel = model
  }

  useEffect(() => {
    if (modelsPending) {
      void manager.fetchModels()
    }
  }, [manager, modelsPending])

  useEffect(() => {
    // After models have loaded, select the default model from local storage, or the default model based on flag states.
    if (!hasSelectedDefaultModel.current && !modelsPending && availableModels.length > 1) {
      const storedModelId = copilotLocalStorage.getModel(selectedThreadID)?.id
      let defaultModel = availableModels.find(
        m => m.id === storedModelId && (shouldShowFallbackModel || storedModelId !== BASE_MODEL_ID),
      )
      if ((!defaultModel && plan) || (premiumInteractionsQuotaExceeded && !overagesEnabled)) {
        defaultModel = getDefaultModel(availableModels, plan, premiumInteractionsQuotaExceeded, overagesEnabled)
      }
      if (defaultModel) {
        manager.selectModel(defaultModel, true)
        hasSelectedDefaultModel.current = true
      }
    }
  }, [
    availableModels,
    manager,
    model,
    modelsPending,
    overagesEnabled,
    plan,
    premiumInteractionsQuotaExceeded,
    selectedThreadID,
    shouldShowFallbackModel,
  ])

  // Load model from URL if it exists
  useEffect(() => {
    if (mode !== 'immersive') return

    const urlSearchParams = new URLSearchParams(search)
    const queryModel = urlSearchParams.get('model')

    if (queryModel && (pathname === '/copilot' || pathname === '/copilot/')) {
      if (model.id === queryModel) return

      const availableModel = availableModels?.find(m => m.id === queryModel)
      if (availableModel) {
        void manager.selectModel(availableModel, false)
        sendEvent('dotcom_chat.activate', {target: 'COPILOT_MODEL_LOADED_FROM_URL', mode: 'immersive'})
      }
    }
    // When the page loads availableModels is empty. Once we fetch the models
    // and availableModels is populated we want this effect to run to update the model.
    // Any other state changes (user picks a different model) should not run this effect again.

    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [availableModels])

  function selectModel(m: CopilotChatModel): void {
    if (onModelSelected) {
      onModelSelected(m)
    } else {
      void manager.selectModel(m)
    }
  }

  // If you don't have at least two models, don't show the picker
  if (availableModels.length < 2) return null

  const onModelPicked = (newModel: CopilotChatModel) => {
    if (type === 'global' && isSameModel(selectedModel, newModel)) return

    sendEvent('dotcom_chat.activate', {
      target: 'MODEL_PICKER_MODEL_SELECT',
      mode: 'immersive',
      model: newModel.id,
      isUnchanged: isSameModel(selectedModel, newModel),
      type,
    })

    if (isSameModel(selectedModel, newModel)) {
      selectModel(newModel)
    } else if (
      modelSwitchingRequiresNewConversationDueToExternalContent(messages, newModel, type === 'message-retry')
    ) {
      setPending({model: newModel, command: {action: 'requires-new-conversation', reason: 'external-content'}})
    } else if (
      modelSwitchingRequiresNewConversationDueToDegradedImageSupport(
        messages,
        currentReferences,
        newModel,
        type === 'message-retry',
      )
    ) {
      setPending({model: newModel, command: {action: 'requires-new-conversation', reason: 'degraded-image-support'}})
    } else if (modelSwitchingRequiresPolicyConfirmation(newModel)) {
      setPending({model: newModel, command: {action: 'requires-policy-approval'}})
    } else {
      selectModel(newModel)
    }
  }

  return (
    <>
      <ModelPickerDesign
        selectedModel={selectedModel}
        models={availableModels}
        type={type}
        onModelPicked={onModelPicked}
        limited={limited}
        disabled={disabled}
        variant={'invisible'}
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
              type,
            })
            setPending(null)
          }}
          onSwitch={async () => {
            sendEvent('dotcom_chat.activate', {
              target: 'MODEL_PICKER_DIALOG_REQUIRES_NEW_CONVERSATION_CONFIRM',
              mode: 'immersive',
              model: pending.model.id,
              type,
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
              type,
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
              type,
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
  type: ModelPickerType
  disabled: boolean
  variant?: 'default' | 'invisible'
  plan?: CopilotPlan
}

export function ModelPickerDesign({
  selectedModel,
  models,
  onModelPicked,
  limited = false,
  type,
  disabled,
  variant = 'invisible',
}: ModelPickerDesignProps) {
  const [isOpen, setIsOpen] = useState(false)

  // Models before base model and premium quotas
  let baseModels: CopilotChatModel[] = []
  let previewModels: CopilotChatModel[] = []
  let upsellModelsToDisplay: UpsellModels = []

  // Models after base model and premium quotas
  let lowTierModels: CopilotChatModel[] = []
  let midTierModels: CopilotChatModel[] = []
  let highTierModels: CopilotChatModel[] = []
  let baseModel: CopilotChatModel | undefined

  const shouldShowModelCategories =
    copilotFeatureFlags.immersiveStructuredModelPicker &&
    models.some(m => m.billing?.multiplier !== undefined) &&
    // Only true if not all models have the same billing multiplier
    new Set(models.filter(m => m.billing?.multiplier !== undefined).map(m => m.billing?.multiplier)).size > 1

  const {premiumInteractionsQuotaExceeded, overagesEnabled} = useEntitlement()
  const shouldShowFallbackModel =
    copilotFeatureFlags.premiumRequestQuotasEnabled && premiumInteractionsQuotaExceeded && !overagesEnabled

  if (shouldShowModelCategories) {
    baseModel = models.find(m => m.id === BASE_MODEL_ID)
    lowTierModels = models.filter(m => m.billing && m.billing?.multiplier < 1 && m !== baseModel)
    midTierModels = models.filter(
      m =>
        (m.billing && m.billing?.multiplier === 1 && !(shouldShowFallbackModel && m.is_chat_default)) ||
        (m.is_chat_fallback && shouldShowFallbackModel),
    )
    highTierModels = models.filter(m => m.billing && m.billing?.multiplier > 1)
  } else {
    baseModels = models.filter(m => !m.preview)
    previewModels = models.filter(m => m.preview)
    upsellModelsToDisplay = limited ? upsellModels : []
  }
  const uniqueVendors = new Set(models.map(m => m.vendor))
  const hasMultipleVendors = uniqueVendors.size > 1
  const hasThirdPartyModel = models.some(m => m.isThirdParty)

  const handleMenuOpen = useCallback(
    (open: boolean) => {
      // In case the retry divider is clicked
      const shouldOpen = !disabled && open
      setIsOpen(shouldOpen)

      if (shouldOpen) {
        sendEvent('dotcom_chat.activate', {
          target: 'MODEL_PICKER_OPEN',
          mode: 'immersive',
          model: selectedModel.id,
          type,
        })
      }
    },
    [disabled, selectedModel.id, type],
  )

  const setVariant = variant ?? 'invisible'

  const componentRef = useRef<HTMLDivElement>(null)
  const [menuDirection, setMenuDirection] = useState<'up' | 'down'>('down')

  const selectedModelDisplayName =
    copilotFeatureFlags.premiumRequestQuotasEnabled && selectedModel.is_chat_fallback
      ? selectedModel.displayName.replace(/ \(Base\)$/, '')
      : selectedModel.displayName

  return (
    <div ref={componentRef}>
      <ActionMenu open={isOpen} onOpenChange={handleMenuOpen}>
        {type === 'global' ? (
          <ActionMenu.Button aria-label={'Switch model'} variant={setVariant} disabled={disabled}>
            <span className="sr-only">Model: </span>
            {selectedModelDisplayName}
          </ActionMenu.Button>
        ) : (
          <ActionMenu.Anchor aria-label={'Retry with model'}>
            <ButtonGroup className={styles.messageRetryButtonGroup}>
              <IconButton
                variant="invisible"
                aria-label={`Retry with ${selectedModelDisplayName}`}
                onClick={() => onModelPicked(selectedModel)}
                icon={SyncIcon}
                disabled={disabled}
                className={styles.messageRetryButton}
              />
              <div className={styles.messageRetryDivider} />
              <IconButton
                variant="invisible"
                icon={TriangleDownIcon}
                aria-label="Retry with…"
                disabled={disabled}
                className={styles.messageRetryMenuButton}
              />
            </ButtonGroup>
          </ActionMenu.Anchor>
        )}

        <ActionMenu.Overlay
          width={type === 'global' ? 'medium' : 'small'}
          align={'end'}
          onPositionChange={({position}) => {
            const downPositions = ['inside-bottom', 'outside-bottom']
            setMenuDirection(downPositions.includes(position.anchorSide) ? 'down' : 'up')
          }}
        >
          <ActionList selectionVariant={type === 'global' ? 'single' : undefined}>
            {type === 'message-retry' && menuDirection === 'down' && (
              <>
                <RetryListItem selectedModel={selectedModel} onModelPicked={onModelPicked} />
                <ActionList.Divider />
              </>
            )}

            {baseModels.length > 0 && (
              <ActionList.Group>
                <ActionList.GroupHeading>Models</ActionList.GroupHeading>
                {baseModels.map(m => (
                  <ModelListItem
                    key={m.id}
                    model={m}
                    selected={isSameModel(selectedModel, m) && type === 'global'}
                    onModelPicked={onModelPicked}
                    hasMultipleVendors={hasMultipleVendors}
                    hasThirdPartyModel={hasThirdPartyModel}
                  />
                ))}
              </ActionList.Group>
            )}

            {lowTierModels.length > 0 && (
              <ActionList.Group>
                <ActionList.GroupHeading>Fast and cost-efficient</ActionList.GroupHeading>

                {lowTierModels.map(m => (
                  <ModelListItem
                    key={m.id}
                    model={m}
                    selected={isSameModel(selectedModel, m) && type === 'global'}
                    onModelPicked={onModelPicked}
                    hasMultipleVendors={hasMultipleVendors}
                    hasThirdPartyModel={hasThirdPartyModel}
                  />
                ))}
                <ActionList.Divider />
              </ActionList.Group>
            )}

            {midTierModels.length > 0 && (
              <ActionList.Group>
                <ActionList.GroupHeading>Versatile and highly intelligent</ActionList.GroupHeading>

                {midTierModels.map(m => (
                  <ModelListItem
                    key={m.id}
                    model={m}
                    selected={isSameModel(selectedModel, m) && type === 'global'}
                    onModelPicked={onModelPicked}
                    hasMultipleVendors={hasMultipleVendors}
                    hasThirdPartyModel={hasThirdPartyModel}
                  />
                ))}
                <ActionList.Divider />
              </ActionList.Group>
            )}

            {highTierModels.length > 0 && (
              <ActionList.Group>
                <ActionList.GroupHeading>Most powerful at complex tasks</ActionList.GroupHeading>

                {highTierModels.map(m => (
                  <ModelListItem
                    key={m.id}
                    model={m}
                    selected={isSameModel(selectedModel, m) && type === 'global'}
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
                    selected={isSameModel(selectedModel, m) && type === 'global'}
                    onModelPicked={onModelPicked}
                    hasMultipleVendors={hasMultipleVendors}
                    hasThirdPartyModel={hasThirdPartyModel}
                  />
                ))}

                {upsellModelsToDisplay.map(m => (
                  <ActionList.LinkItem
                    key={m.id}
                    href={
                      copilotFeatureFlags.freeToPaidUpgradeToProFromModels ? UPGRADE_TO_PRO_PLAN_URL : UPGRADE_PLAN_URL
                    }
                  >
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

            {type === 'message-retry' && menuDirection === 'up' && (
              <>
                <ActionList.Divider />
                <RetryListItem selectedModel={selectedModel} onModelPicked={onModelPicked} />
              </>
            )}
          </ActionList>
          {copilotFeatureFlags.premiumRequestQuotasEnabled && <ModelPickerFooter />}
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  )
}

function ModelPickerFooter() {
  const {
    plan,
    premiumChatQuotaRemaining,
    premiumInteractionsQuotaExceeded,
    chatQuotaRemaining,
    chatQuotaExceeded,
    canPurchaseAdditionalQuota,
    canUpgradePlan,
    overagesEnabled,
    resetDate,
  } = useEntitlement()
  let footerContent = null
  if (plan === CopilotPlan.IndividualFree) {
    if (chatQuotaExceeded) {
      footerContent = (
        <>
          You have used all requests available this month.{' '}
          <Link inline href={UPGRADE_PLAN_URL}>
            Upgrade
          </Link>
          .
        </>
      )
    } else if (chatQuotaRemaining <= FREE_QUOTA_TRIGGER) {
      footerContent = (
        <>
          You have used {100 - FREE_QUOTA_TRIGGER}% of your free requests this month.{' '}
          <Link inline href={UPGRADE_PLAN_URL}>
            Upgrade
          </Link>{' '}
          to increase your limit.
        </>
      )
    } else {
      footerContent = (
        <>
          <Link inline href={UPGRADE_PLAN_URL}>
            Upgrade
          </Link>{' '}
          to get access to more models and higher limits.
        </>
      )
    }
  }
  if (plan === CopilotPlan.IndividualPro) {
    if (premiumInteractionsQuotaExceeded && overagesEnabled) {
      footerContent = (
        <>
          You have used all premium requests available this month. You will be charged per premium request until the
          limit resets on {resetDate}.{' '}
          <Link inline href={MANAGE_BILLING_URL}>
            Manage billing
          </Link>
        </>
      )
    } else if (premiumInteractionsQuotaExceeded && !overagesEnabled) {
      footerContent = (
        <>
          You have used all premium requests available this month.{' '}
          <Link inline href={UPGRADE_PLAN_URL}>
            Upgrade
          </Link>{' '}
          to increase your limit. Limit resets on {resetDate}.
        </>
      )
    } else if (premiumChatQuotaRemaining <= PREMIUM_QUOTA_TRIGGER && !overagesEnabled) {
      footerContent = (
        <>
          You have used {100 - PREMIUM_QUOTA_TRIGGER}% of your premium requests this month.{' '}
          <Link inline href={UPGRADE_PLAN_URL}>
            Upgrade
          </Link>{' '}
          to increase your limit.
        </>
      )
    }
  }
  if (plan === CopilotPlan.IndividualProPlus) {
    if (premiumInteractionsQuotaExceeded && overagesEnabled) {
      footerContent = (
        <>
          You have used all premium requests available this month. You will be charged per premium request until the
          limit resets on {resetDate}.{' '}
          <Link inline href={MANAGE_BILLING_URL}>
            Manage billing
          </Link>
        </>
      )
    } else if (premiumInteractionsQuotaExceeded && !overagesEnabled) {
      footerContent = (
        <>
          You have used all premium requests available this month.{' '}
          <Link inline href={ENABLE_ADDITIONAL_REQUESTS_URL}>
            Enable additional requests
          </Link>{' '}
          to get more. Limit resets on {resetDate}.
        </>
      )
    } else if (premiumChatQuotaRemaining <= PREMIUM_QUOTA_TRIGGER && !overagesEnabled) {
      footerContent = (
        <>
          You have used {100 - PREMIUM_QUOTA_TRIGGER}% of your premium requests this month.{' '}
          <Link inline href={ENABLE_ADDITIONAL_REQUESTS_URL}>
            Enable additional requests
          </Link>{' '}
          to get more.
        </>
      )
    }
  }
  if (plan === CopilotPlan.Business) {
    if (premiumInteractionsQuotaExceeded && !overagesEnabled && canUpgradePlan) {
      footerContent = (
        <>
          You have used all premium requests available this month.{' '}
          <Link inline href={UPGRADE_PLAN_URL}>
            Upgrade
          </Link>{' '}
          to increase your limit. Limit resets on {resetDate}.
        </>
      )
    } else if (premiumChatQuotaRemaining <= PREMIUM_QUOTA_TRIGGER && !overagesEnabled && canUpgradePlan) {
      footerContent = (
        <>
          You have used {100 - PREMIUM_QUOTA_TRIGGER}% of your premium requests this month.{' '}
          <Link inline href={UPGRADE_PLAN_URL}>
            Upgrade
          </Link>{' '}
          to increase your limit.
        </>
      )
    } else if (premiumInteractionsQuotaExceeded && !overagesEnabled && !canUpgradePlan) {
      footerContent = (
        <>
          You have reached your monthly limit for premium requests.{' '}
          <span className="font-weight-bold">Ask your admin to upgrade </span>
          to increase your limit. Limit resets on {resetDate}.
        </>
      )
    } else if (premiumChatQuotaRemaining <= PREMIUM_QUOTA_TRIGGER && !overagesEnabled && !canUpgradePlan) {
      footerContent = (
        <>
          You have used {100 - PREMIUM_QUOTA_TRIGGER}% of your premium requests this month.{' '}
          <span className="font-weight-bold">Ask your admin to upgrade </span>
          to increase your limit.
        </>
      )
    }
  }
  if (plan === CopilotPlan.Enterprise) {
    if (premiumInteractionsQuotaExceeded && !overagesEnabled && canPurchaseAdditionalQuota) {
      footerContent = (
        <>
          You have used all premium requests available this month.{' '}
          <Link inline href={ENABLE_ADDITIONAL_REQUESTS_URL}>
            Enable additional requests
          </Link>{' '}
          to increase your limit. Limit resets on {resetDate}.
        </>
      )
    } else if (premiumInteractionsQuotaExceeded && !overagesEnabled && !canPurchaseAdditionalQuota) {
      footerContent = (
        <>
          You have reached your monthly limit for premium requests. Ask your admin to{' '}
          <span className="font-weight-bold">enable additional requests </span>
          to get more usage. Limit resets on {resetDate}.
        </>
      )
    } else if (premiumChatQuotaRemaining <= PREMIUM_QUOTA_TRIGGER && !overagesEnabled && canPurchaseAdditionalQuota) {
      footerContent = (
        <>
          You have used {100 - PREMIUM_QUOTA_TRIGGER}% of your premium requests this month.{' '}
          <Link inline href={ENABLE_ADDITIONAL_REQUESTS_URL}>
            Enable additional requests
          </Link>{' '}
          to get more usage after the limit is reached.
        </>
      )
    } else if (premiumChatQuotaRemaining <= PREMIUM_QUOTA_TRIGGER && !overagesEnabled && !canPurchaseAdditionalQuota) {
      footerContent = (
        <>
          You have used {100 - PREMIUM_QUOTA_TRIGGER}% of your premium requests this month. Ask your admin to{' '}
          <span className="font-weight-bold">enable additional requests </span>
          to get more usage.
        </>
      )
    }
  }

  return footerContent ? <div className={styles.footer}>{footerContent}</div> : null
}

interface RetryListItemProps {
  selectedModel: CopilotChatModel
  onModelPicked: (m: CopilotChatModel) => void
}

function RetryListItem({selectedModel, onModelPicked}: RetryListItemProps) {
  return (
    <ActionList.Item key={selectedModel.id} onSelect={() => onModelPicked(selectedModel)}>
      <ActionList.LeadingVisual>
        <SyncIcon />
      </ActionList.LeadingVisual>
      Try again
      <ActionList.Description variant="block" truncate>
        {selectedModel.displayName}
      </ActionList.Description>
    </ActionList.Item>
  )
}

interface ModelListItemProps {
  model: CopilotChatModel
  selected: boolean
  onModelPicked: (m: CopilotChatModel) => void
  hasMultipleVendors: boolean
  hasThirdPartyModel: boolean
}

export function ModelListItem({
  model,
  selected,
  onModelPicked,
  hasMultipleVendors,
  hasThirdPartyModel,
}: ModelListItemProps) {
  const {plan, premiumInteractionsQuotaExceeded, chatQuotaExceeded, overagesEnabled} = useEntitlement()
  const freePlanAndOutOfQuota = plan === CopilotPlan.IndividualFree && chatQuotaExceeded
  const premiumModelAndOutOfQuota = model.billing?.is_premium && premiumInteractionsQuotaExceeded && !overagesEnabled
  const modelOutOfPlan = plan && model.billing?.restricted_to && !model.billing?.restricted_to.includes(plan)
  const locked = freePlanAndOutOfQuota || premiumModelAndOutOfQuota || modelOutOfPlan
  return (
    <ActionList.Item key={model.id} onSelect={() => onModelPicked(model)} selected={selected} disabled={!!locked}>
      {(hasMultipleVendors || hasThirdPartyModel) && (
        <ActionList.LeadingVisual>
          <ModelVendorIcon model={model} />
        </ActionList.LeadingVisual>
      )}
      <span className={styles.modelName}>
        {copilotFeatureFlags.premiumRequestQuotasEnabled && model.is_chat_fallback
          ? model.displayName.replace(/ \(Base\)$/, '')
          : model.displayName}
      </span>
      {copilotFeatureFlags.premiumRequestQuotasEnabled && model.is_chat_fallback && (
        <span className={styles.modelMetaLabel}>Base</span>
      )}
      {copilotFeatureFlags.premiumRequestQuotasEnabled && model.preview && model.id !== BASE_MODEL_ID && (
        <span className={styles.modelMetaLabel}>Preview</span>
      )}
      {copilotFeatureFlags.premiumRequestQuotasEnabled && locked && (
        <ActionList.TrailingVisual>
          <LockIcon />
        </ActionList.TrailingVisual>
      )}
      {!copilotFeatureFlags.premiumRequestQuotasEnabled && (hasMultipleVendors || hasThirdPartyModel) && (
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

function modelSwitchingRequiresNewConversationDueToExternalContent(
  messages: readonly CopilotChatMessage[],
  model: CopilotChatModel,
  onlyActiveMessages?: boolean,
): boolean {
  const messagesToCheck = onlyActiveMessages ? getActiveMessages(messages) : messages
  const hasFunctionCalls = messagesToCheck.some(message => message.skillExecutions?.length)

  return (
    hasFunctionCalls &&
    (!model.capabilities.supports.tool_calls ||
      model.isThirdParty ||
      // TODO: temporary - o1-ga supports tool calling, but the dotcom chat code in CAPI currently does not
      // As of 2024-12-17 we expect this to be done in a few business days
      model.capabilities.family === 'o1-ga')
  )
}

function modelSwitchingRequiresNewConversationDueToDegradedImageSupport(
  messages: readonly CopilotChatMessage[],
  currentReferences: CopilotChatReference[],
  model: CopilotChatModel,
  onlyActiveMessages?: boolean,
): boolean {
  const messagesToCheck = onlyActiveMessages ? getActiveMessages(messages) : messages
  const hasMediaContent =
    messagesToCheck.some(message => message.mediaContent?.length) || currentReferences.some(cr => cr.type === 'image')

  return hasMediaContent && !model.capabilities.supports.vision
}

function modelSwitchingRequiresPolicyConfirmation(m: CopilotChatModel): boolean {
  return !!m.policy && m.policy.state !== 'enabled'
}

function isSameModel(oldModel: CopilotChatModel, newModel: CopilotChatModel): boolean {
  return oldModel.id === newModel.id
}

// TODO: We are hard-coding these until CAPI supports returning models the user does not currently have access to.
// This work should be done by February 2025. If this code still exists after that, something has changed.
type UpsellModels = Array<Pick<CopilotChatModel, 'logoURL' | 'displayName' | 'vendor' | 'id'>>
const upsellModels: UpsellModels = [
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
