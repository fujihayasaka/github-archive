import {Box, Button, FormControl, RadioGroup, Radio, Stack, Checkbox} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {formBoxStyle, Spacing} from '../helpers/style'
import {useState} from 'react'
import type {
  ImageDefinition,
  OsType,
  Architecture,
  ImageDefinitionEnabled,
  CreateCuratedImagePayload,
  UpdateCuratedImagePayload,
  OwnerId,
} from '../types/types'
import {validateImageDefinitionName, getImageDefinitionEnabledStatus, validateFeatureFlag} from '../helpers/utils'
import {FeatureFlagInput} from './FeatureFlagInput'
import {ImageDefinitionNameInput} from './ImageDefinitionNameInput'
import {createCuratedImageDefinition, updateCuratedImageDefinition} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {rootUrlForOwnerId} from '../helpers/urls'

import styles from './NewEditCuratedImageDialog.module.css'

interface NewEditCuratedImageDialogProps {
  curatedOwner: OwnerId
  curatedImage?: ImageDefinition
  closeDialog: () => void
}

export function NewEditCuratedImageDialog(props: NewEditCuratedImageDialogProps) {
  const [name, setName] = useState(props.curatedImage?.name || '')
  const [osType, setOsType] = useState<OsType>((props.curatedImage?.osType as OsType) || 'Linux')
  const [architecture, setArchitecture] = useState<Architecture>(props.curatedImage?.architecture ?? 'X64')
  const [enabled, setEnabled] = useState<ImageDefinitionEnabled>(() =>
    props.curatedImage ? getImageDefinitionEnabledStatus(props.curatedImage) : 'Enabled',
  )
  const [featureFlag, setFeatureFlag] = useState(props.curatedImage?.featureFlag || '')
  const [isImageGenerationSupported, setIsImageGenerationSupported] = useState(
    props.curatedImage?.isImageGenerationSupported ?? false,
  )

  const flashBanner = useFlashBannerState()

  const isUpdateAction = Boolean(props.curatedImage)
  const dialogConstants = isUpdateAction
    ? {
        dialogTitle: 'Edit curated image',
        submitButton: 'Update',
        successBanner: 'Image has been updated',
      }
    : {
        dialogTitle: 'New curated image',
        submitButton: 'Create',
        successBanner: 'Image has been created',
      }

  const isFormValid = validateImageDefinitionName(name) && validateFeatureFlag(enabled, featureFlag)

  const handleSubmit = async () => {
    flashBanner.hide()

    if (!isFormValid) {
      return
    }

    const payload: CreateCuratedImagePayload = {
      name,
      ownerId: props.curatedOwner,
      osType,
      architecture,
      enabled: enabled === 'Enabled',
      featureFlag,
      isImageGenerationSupported,
    }
    let response = null

    if (isUpdateAction && props.curatedImage?.id) {
      const updatePayload: UpdateCuratedImagePayload = {
        ...payload,
        id: props.curatedImage?.id,
      }
      response = await updateCuratedImageDefinition(updatePayload)
    } else {
      response = await createCuratedImageDefinition(payload)
    }
    if (response.ok) {
      flashBanner.showInfo(dialogConstants.successBanner)
      window.location.assign(rootUrlForOwnerId(props.curatedOwner))
    } else {
      flashBanner.showError(response.error)
    }
  }

  return (
    <Dialog isOpen onDismiss={() => props.closeDialog()}>
      <Dialog.Header>
        {dialogConstants.dialogTitle} {props.curatedImage ? `(ID ${props.curatedImage.id})` : ''}
      </Dialog.Header>
      <Box sx={{p: Spacing.StandardPadding}}>
        <FlashBanner state={flashBanner.state} />
        <Box sx={formBoxStyle}>
          <ImageDefinitionNameInput name={name} onNameChange={setName} />
          <RadioGroup name="ownerId" disabled>
            <RadioGroup.Label className={styles.RadioGroup_Label}>OwnerId</RadioGroup.Label>
            <Stack direction="horizontal">
              <FormControl>
                <Radio value="github" checked={props.curatedOwner === 'github'} />
                <FormControl.Label sx={{fontWeight: 400}}>GitHub</FormControl.Label>
              </FormControl>
              <FormControl>
                <Radio value="partner" checked={props.curatedOwner === 'partner'} />
                <FormControl.Label sx={{fontWeight: 400}}>Partner</FormControl.Label>
              </FormControl>
              <FormControl>
                <Radio value="azuredevops" checked={props.curatedOwner === 'azuredevops'} />
                <FormControl.Label sx={{fontWeight: 400}}>Azure DevOps</FormControl.Label>
              </FormControl>
            </Stack>
          </RadioGroup>
          <RadioGroup name="osType" onChange={value => setOsType(value as OsType)} disabled={isUpdateAction}>
            <RadioGroup.Label className={styles.RadioGroup_Label}>OsType</RadioGroup.Label>
            <Stack direction="horizontal">
              <FormControl>
                <Radio value="Linux" checked={osType === 'Linux'} />
                <FormControl.Label sx={{fontWeight: 400}}>Linux</FormControl.Label>
              </FormControl>
              <FormControl>
                <Radio value="Windows" checked={osType === 'Windows'} />
                <FormControl.Label sx={{fontWeight: 400}}>Windows</FormControl.Label>
              </FormControl>
              <FormControl>
                <Radio value="MacOS" checked={osType === 'MacOS'} />
                <FormControl.Label sx={{fontWeight: 400}}>MacOS</FormControl.Label>
              </FormControl>
            </Stack>
          </RadioGroup>
          <RadioGroup
            name="architecture"
            onChange={value => setArchitecture(value as Architecture)}
            disabled={isUpdateAction}
          >
            <RadioGroup.Label className={styles.RadioGroup_Label}>Architecture</RadioGroup.Label>
            <Stack direction="horizontal">
              <FormControl>
                <Radio value="X64" checked={architecture === 'X64'} />
                <FormControl.Label sx={{fontWeight: 400}}>X64</FormControl.Label>
              </FormControl>
              <FormControl>
                <Radio value="Arm64" checked={architecture === 'Arm64'} />
                <FormControl.Label sx={{fontWeight: 400}}>Arm64</FormControl.Label>
              </FormControl>
            </Stack>
          </RadioGroup>
          <FeatureFlagInput
            enabled={enabled}
            featureFlag={featureFlag}
            onEnabledChange={setEnabled}
            onFeatureFlagChange={setFeatureFlag}
          />
          <FormControl>
            <FormControl.Label htmlFor="enable-image-generation">Enable image generation</FormControl.Label>
            <Checkbox
              id="enable-image-generation"
              checked={isImageGenerationSupported}
              onChange={e => setIsImageGenerationSupported(e.target.checked)}
              aria-label="Enable image generation"
            />
          </FormControl>
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
