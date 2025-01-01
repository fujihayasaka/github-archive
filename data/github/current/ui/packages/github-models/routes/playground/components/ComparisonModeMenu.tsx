import {ActionList, ActionMenu, Box, Checkbox, FormControl, IconButton, Text} from '@primer/react'
import {SlidersIcon, TrashIcon} from '@primer/octicons-react'
import ModelParameters from './ModelParameters'
import {usePlaygroundManager} from '../../../utils/playground-manager'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {validateAndFilterParameters} from '../../../utils/model-state'
import type {ModelState} from '../../../types'

interface ComparisonModeMenuProps {
  modelState: ModelState
  position: number
}

export const ComparisonModeMenu = ({modelState, position}: ComparisonModeMenuProps) => {
  const {models, syncInputs} = usePlaygroundState()
  const {parametersHasChanges} = modelState
  const manager = usePlaygroundManager()

  const toggleSyncInputs = () => {
    const newSyncInputs = !syncInputs

    if (newSyncInputs && models.length > 1) {
      // We need to ensure the other models have the same parameters as this one
      for (const [index, otherModelState] of models.entries()) {
        if (index === position) continue // Skip the current model

        manager.setModelState(index, {
          ...otherModelState,
          systemPrompt: modelState.systemPrompt,
          isUseIndexSelected: modelState.isUseIndexSelected,
          parameters: validateAndFilterParameters(
            otherModelState.modelInputSchema?.parameters || [],
            modelState.parameters,
          ),
          chatInput: modelState.chatInput,
        })
      }
    }

    manager.setSyncInputs(newSyncInputs)
  }

  return (
    <>
      <ActionMenu
        onOpenChange={(isOpen: boolean) => {
          const {parameters: schema = []} = modelState.modelInputSchema || {}
          if (isOpen || schema.length === 0 || !modelState.parametersHasChanges) return

          // Ensure validation when menu is closed, as it may not have occurred yet
          for (const [index, {modelInputSchema = {}, parameters}] of models.entries()) {
            if (syncInputs || index === position) {
              manager.setParameters(index, validateAndFilterParameters(modelInputSchema.parameters || [], parameters))
            }
          }
        }}
      >
        <ActionMenu.Anchor>
          <IconButton icon={SlidersIcon} size="small" aria-label="Show parameters setting" />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay width="xlarge" side="outside-left">
          <ActionList>
            <div
              className="d-flex flex-items-center border-bottom borderColor-default px-3 py-2"
              style={{minHeight: '49px'}} // This is to prevent the height from changing when the reset button appears
            >
              <Text as="h1" sx={{fontSize: 1, fontWeight: 'bold', flex: 1}}>
                Parameters
              </Text>
              <div className="d-flex gap-2 flex-items-center">
                <Box sx={{display: 'flex'}}>
                  {(modelState.modelInputSchema?.parameters?.length !== 0 ||
                    modelState.modelInputSchema?.capabilities?.systemPrompt) &&
                    parametersHasChanges && (
                      <IconButton
                        icon={TrashIcon}
                        as="button"
                        variant="invisible"
                        disabled={!parametersHasChanges}
                        aria-label="Reset to default inputs"
                        onClick={() => {
                          const currentModelDetails = {
                            catalogData: modelState.catalogData,
                            modelInputSchema: modelState.modelInputSchema,
                            gettingStarted: modelState.gettingStarted,
                          }

                          for (const [index] of models.entries()) {
                            if (index === position || syncInputs) {
                              manager.resetParamsAndSystemPrompt(index, currentModelDetails)
                            }
                          }
                        }}
                      />
                    )}
                </Box>
                <form>
                  <FormControl>
                    <Checkbox value="default" checked={syncInputs} onChange={toggleSyncInputs} />
                    <FormControl.Label>Sync chat input and parameters</FormControl.Label>
                  </FormControl>
                </form>
              </div>
            </div>
            <ModelParameters model={modelState} position={position} />
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
}
