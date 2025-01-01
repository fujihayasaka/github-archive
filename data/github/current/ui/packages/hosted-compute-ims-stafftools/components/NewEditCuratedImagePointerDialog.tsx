import {Box, Button, FormControl, Select} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {formBoxStyle, Spacing} from '../helpers/style'
import type {
  ImageDefinition,
  ImageDefinitionEnabled,
  UpdateCuratedImagePointerPayload,
  CreateCuratedImagePointerPayload,
} from '../types/types'
import {useState} from 'react'
import {CuratedImagePointerDialogConstants} from '../helpers/constants'
import {
  splitCuratedImageDefinitions,
  validateImageDefinitionName,
  getImageDefinitionEnabledStatus,
  validateFeatureFlag,
} from '../helpers/utils'
import {FeatureFlag} from './FeatureFlag'
import {NameInput} from './NameInput'
import {createCuratedImageDefinitionPointer, updateCuratedImageDefinitionPointer} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {homepagePath} from '../helpers/paths'

interface CreateEditCuratedImagePointerDialogProps {
  closeDialog: () => void
  imageDefinitions: ImageDefinition[]
  imagePointer?: ImageDefinition | null
}

export function NewEditCuratedImagePointerDialog(props: CreateEditCuratedImagePointerDialogProps) {
  const {imageDefinitionsList} = splitCuratedImageDefinitions(props.imageDefinitions)

  const [name, setName] = useState(props.imagePointer?.name ?? '')
  const [pointsToImageDefinitionId, setPointsToImageDefinitionId] = useState(
    props.imagePointer?.pointsToImageDefinitionId ?? imageDefinitionsList[0]?.id,
  )
  const [enabled, setEnabled] = useState<ImageDefinitionEnabled>(() =>
    props.imagePointer ? getImageDefinitionEnabledStatus(props.imagePointer) : 'Enabled',
  )
  const [featureFlag, setFeatureFlag] = useState(props.imagePointer?.featureFlag || '')
  const flashBanner = useFlashBannerState()

  const isUpdateAction = Boolean(props.imagePointer)
  const dialogConstants = isUpdateAction
    ? CuratedImagePointerDialogConstants.Edit
    : CuratedImagePointerDialogConstants.New

  const isFormValid = validateImageDefinitionName(name) && validateFeatureFlag(enabled, featureFlag)

  const handleSubmit = async () => {
    flashBanner.hide()

    if (!isFormValid) {
      return
    }

    const payload = {
      name,
      pointsToImageDefinitionId,
      enabled: enabled === 'Enabled',
      featureFlag,
    }
    let response = null

    if (isUpdateAction && props.imagePointer?.id) {
      const updatePayload: UpdateCuratedImagePointerPayload = {
        ...payload,
        id: props.imagePointer?.id,
      }
      response = await updateCuratedImageDefinitionPointer(updatePayload)
    } else {
      response = await createCuratedImageDefinitionPointer(payload as CreateCuratedImagePointerPayload)
    }
    if (response.ok) {
      flashBanner.showInfo(dialogConstants.successBanner)
      window.location.assign(homepagePath())
    } else {
      flashBanner.showError(response.error)
    }
  }
  return (
    <Dialog isOpen onDismiss={() => props.closeDialog()}>
      <Dialog.Header>
        {dialogConstants.dialogTitle} {props.imagePointer ? `(ID ${props.imagePointer.id})` : ''}
      </Dialog.Header>
      <Box sx={{p: Spacing.StandardPadding}}>
        <FlashBanner state={flashBanner.state} />
        <Box sx={formBoxStyle}>
          <NameInput name={name} onNameChange={setName} />
          <FormControl required>
            <FormControl.Label>Points to Image Definition Id</FormControl.Label>
            <Select
              name="pointsToImageDefinitionId"
              value={pointsToImageDefinitionId}
              onChange={e => setPointsToImageDefinitionId(Number(e.target.value))}
            >
              {imageDefinitionsList.map(image => (
                <Select.Option key={image.id} value={image.id.toString()}>
                  {image.name} (ID {image.id})
                </Select.Option>
              ))}
            </Select>
          </FormControl>
          <FeatureFlag
            enabled={enabled}
            featureFlag={featureFlag}
            onEnabledChange={setEnabled}
            onFeatureFlagChange={setFeatureFlag}
          />
        </Box>
        <Box sx={{pt: 3}}>
          <Button variant="primary" onClick={handleSubmit} disabled={!isFormValid}>
            {dialogConstants.submitButton}
          </Button>
        </Box>
      </Box>
    </Dialog>
  )
}
