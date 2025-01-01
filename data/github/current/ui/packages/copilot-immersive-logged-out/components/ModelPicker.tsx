import {ModelListItem} from '@github-ui/copilot-chat/components/ModelPicker'
import type {CopilotChatModel} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {toCopilotChatModels} from '@github-ui/copilot-chat/utils/models'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ActionList, ActionMenu, Button} from '@primer/react'
import {useCallback, useEffect, useRef, useState} from 'react'

import {useCopilotContext} from '../contexts/CopilotContext'
import type {CopilotImmersiveLoggedOutPayload} from '../copilot-immersive-logged-out-types'
import styles from './ModelPicker.module.css'
import {SignInDialog} from './SignInDialog'

function isSameModel(oldModel: CopilotChatModel, newModel: CopilotChatModel): boolean {
  return oldModel.id === newModel.id
}

export const ModelPicker = ({initialModelID}: {initialModelID?: string | null}) => {
  const payload = useAppPayload<CopilotImmersiveLoggedOutPayload>()
  const models = toCopilotChatModels(payload?.models).filter(m => m.model_picker_enabled && !m.preview)
  const uniqueVendors = new Set(models.map(m => m.vendor))
  const hasMultipleVendors = uniqueVendors.size > 1
  const hasThirdPartyModel = models.some(m => m.isThirdParty)

  const [openPicker, setOpenPicker] = useState(false)
  const [openDialog, setOpenDialog] = useState(false)
  const {selectedModel, setSelectedModel} = useCopilotContext()
  const initialModelSet = useRef(false)

  const pickModel = useCallback(
    (model: CopilotChatModel) => {
      if (isSameModel(selectedModel, model)) return
      setSelectedModel(model)
    },
    [selectedModel, setSelectedModel],
  )

  useEffect(() => {
    if (initialModelID && !initialModelSet.current) {
      initialModelSet.current = true
      const initialModel = models.find(m => m.id === initialModelID)
      if (initialModel) pickModel(initialModel)
    }
  }, [initialModelID, models, pickModel])

  return (
    <>
      <div data-testid="model-picker">
        <ActionMenu open={openPicker} onOpenChange={setOpenPicker}>
          <ActionMenu.Button variant="invisible">{selectedModel.displayName}</ActionMenu.Button>
          <ActionMenu.Overlay width="medium" align="center">
            <ActionList selectionVariant="single">
              <ActionList.Group>
                <ActionList.GroupHeading>Models</ActionList.GroupHeading>
                {models.map(model => (
                  <ModelListItem
                    key={model.id}
                    model={model}
                    selected={isSameModel(selectedModel, model)}
                    onModelPicked={pickModel}
                    hasMultipleVendors={hasMultipleVendors}
                    hasThirdPartyModel={hasThirdPartyModel}
                  />
                ))}
                <div className={styles.footer}>
                  <Button
                    variant="link"
                    onClick={() => {
                      setOpenDialog(true)
                      setOpenPicker(false)
                    }}
                  >
                    Sign in or create an account
                  </Button>
                  {` to discover more options.`}
                </div>
              </ActionList.Group>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </div>
      {openDialog && <SignInDialog onClose={() => setOpenDialog(false)} />}
    </>
  )
}
