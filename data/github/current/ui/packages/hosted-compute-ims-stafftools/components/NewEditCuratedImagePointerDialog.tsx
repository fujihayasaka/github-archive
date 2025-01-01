import {Box, Button, FormControl, Radio, RadioGroup, Select, Stack} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {formBoxStyle, Spacing} from '../helpers/style'
import type {
  ImageDefinition,
  ImageDefinitionEnabled,
  UpdateCuratedImagePointerPayload,
  CreateCuratedImagePointerPayload,
  OwnerId,
} from '../types/types'
import {useState} from 'react'
import {validateImageDefinitionName, getImageDefinitionEnabledStatus, validateFeatureFlag} from '../helpers/utils'
import {FeatureFlagInput} from './FeatureFlagInput'
import {ImageDefinitionNameInput} from './ImageDefinitionNameInput'
import {createCuratedImageDefinitionPointer, updateCuratedImageDefinitionPointer} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {rootUrl} from '../helpers/urls'
import styles from './NewEditCuratedImageDialog.module.css'

interface CreateEditCuratedImagePointerDialogProps {
  pointerImage?: ImageDefinition | null
  referencedImagesCandidates: ImageDefinition[]
  pointerOwner: OwnerId
  closeDialog: () => void
}

export function NewEditCuratedImagePointerDialog(props: CreateEditCuratedImagePointerDialogProps) {
  const referencedImagesCandidates = props.referencedImagesCandidates
    .filter(
      x =>
        !props.pointerImage ||
        (x.osType === props.pointerImage.osType && x.architecture === props.pointerImage.architecture),
    )
    .sort((a, b) => a.ownerId.localeCompare(b.ownerId) || a.name.localeCompare(b.name))

  const [name, setName] = useState(props.pointerImage?.name ?? '')
  const [pointsToImageDefinitionId, setPointsToImageDefinitionId] = useState(
    props.pointerImage?.pointsToImageDefinitionId ?? referencedImagesCandidates[0]?.id,
  )
  const [enabled, setEnabled] = useState<ImageDefinitionEnabled>(() =>
    props.pointerImage ? getImageDefinitionEnabledStatus(props.pointerImage) : 'Enabled',
  )
  const [featureFlag, setFeatureFlag] = useState(props.pointerImage?.featureFlag || '')
  const flashBanner = useFlashBannerState()

  const isUpdateAction = Boolean(props.pointerImage)
  const dialogConstants = isUpdateAction
    ? {
        dialogTitle: 'Edit curated image pointer',
        submitButton: 'Update',
        successBanner: 'Image pointer has been updated',
      }
    : {
        dialogTitle: 'New curated image pointer',
        submitButton: 'Create',
        successBanner: 'Image pointer has been created',
      }

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

    if (isUpdateAction && props.pointerImage?.id) {
      const updatePayload: UpdateCuratedImagePointerPayload = {
        ...payload,
        id: props.pointerImage?.id,
      }
      response = await updateCuratedImageDefinitionPointer(updatePayload)
    } else {
      const createPayload: CreateCuratedImagePointerPayload = {
        ...payload,
        ownerId: props.pointerOwner,
      }
      response = await createCuratedImageDefinitionPointer(createPayload)
    }
    if (response.ok) {
      flashBanner.showInfo(dialogConstants.successBanner)
      window.location.assign(rootUrl('pointers'))
    } else {
      flashBanner.showError(response.error)
    }
  }
  return (
    <Dialog isOpen onDismiss={() => props.closeDialog()}>
      <Dialog.Header>
        {dialogConstants.dialogTitle} {props.pointerImage ? `(ID ${props.pointerImage.id})` : ''}
      </Dialog.Header>
      <Box sx={{p: Spacing.StandardPadding}}>
        <FlashBanner state={flashBanner.state} />
        <Box sx={formBoxStyle}>
          <ImageDefinitionNameInput name={name} onNameChange={setName} />
          <RadioGroup name="ownerId" disabled>
            <RadioGroup.Label className={styles.RadioGroup_Label}>OwnerId</RadioGroup.Label>
            <Stack direction="horizontal">
              <FormControl>
                <Radio value="github" checked={props.pointerOwner === 'github'} />
                <FormControl.Label sx={{fontWeight: 400}}>GitHub</FormControl.Label>
              </FormControl>
              <FormControl>
                <Radio value="partner" checked={props.pointerOwner === 'partner'} />
                <FormControl.Label sx={{fontWeight: 400}}>Partner</FormControl.Label>
              </FormControl>
            </Stack>
          </RadioGroup>
          <FormControl required>
            <FormControl.Label>Points to Image Definition Id</FormControl.Label>
            <Select
              name="pointsToImageDefinitionId"
              value={pointsToImageDefinitionId}
              onChange={e => setPointsToImageDefinitionId(Number(e.target.value))}
            >
              {referencedImagesCandidates.map(image => (
                <Select.Option key={image.id} value={image.id.toString()}>
                  {image.ownerId} - {image.name} (ID {image.id})
                </Select.Option>
              ))}
            </Select>
          </FormControl>
          <FeatureFlagInput
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
