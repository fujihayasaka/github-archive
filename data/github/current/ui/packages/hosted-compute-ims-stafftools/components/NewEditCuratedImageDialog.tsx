import {Box, Button, FormControl, RadioGroup, Radio} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {formBoxStyle, Spacing, rowStyle} from '../helpers/style'
import {useState} from 'react'
import type {
  ImageDefinition,
  OsType,
  Architecture,
  ImageDefinitionEnabled,
  CreateCuratedImagePayload,
  UpdateCuratedImagePayload,
} from '../types/types'
import {CuratedImageDialogConstants} from '../helpers/constants'
import {validateImageDefinitionName, getImageDefinitionEnabledStatus, validateFeatureFlag} from '../helpers/utils'
import {FeatureFlag} from './FeatureFlag'
import {NameInput} from './NameInput'
import {createCuratedImageDefinition, updateCuratedImageDefinition} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {homepagePath} from '../helpers/paths'

interface NewEditCuratedImageDialogProps {
  closeDialog: () => void
  imageDefinition?: ImageDefinition
}

export function NewEditCuratedImageDialog(props: NewEditCuratedImageDialogProps) {
  const [name, setName] = useState(props.imageDefinition?.name || '')
  const [osType, setOsType] = useState<OsType>((props.imageDefinition?.osType as OsType) || 'Linux')
  const [architecture, setArchitecture] = useState<Architecture>(props.imageDefinition?.architecture ?? 'X64')
  const [enabled, setEnabled] = useState<ImageDefinitionEnabled>(() =>
    props.imageDefinition ? getImageDefinitionEnabledStatus(props.imageDefinition) : 'Enabled',
  )
  const [featureFlag, setFeatureFlag] = useState(props.imageDefinition?.featureFlag || '')
  const flashBanner = useFlashBannerState()

  const isUpdateAction = Boolean(props.imageDefinition)
  const dialogConstants = isUpdateAction ? CuratedImageDialogConstants.Edit : CuratedImageDialogConstants.New

  const isFormValid = validateImageDefinitionName(name) && validateFeatureFlag(enabled, featureFlag)

  const handleSubmit = async () => {
    flashBanner.hide()

    if (!isFormValid) {
      return
    }

    const payload: CreateCuratedImagePayload = {
      name,
      osType,
      architecture,
      enabled: enabled === 'Enabled',
      featureFlag,
    }
    let response = null

    if (isUpdateAction && props.imageDefinition?.id) {
      const updatePayload: UpdateCuratedImagePayload = {
        ...payload,
        id: props.imageDefinition?.id,
      }
      response = await updateCuratedImageDefinition(updatePayload)
    } else {
      response = await createCuratedImageDefinition(payload)
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
        {dialogConstants.dialogTitle} {props.imageDefinition ? `(ID ${props.imageDefinition.id})` : ''}
      </Dialog.Header>
      <Box sx={{p: Spacing.StandardPadding}}>
        <FlashBanner state={flashBanner.state} />
        <Box sx={formBoxStyle}>
          <NameInput name={name} onNameChange={setName} />
          <RadioGroup name="osType" onChange={value => setOsType(value as OsType)} disabled={isUpdateAction}>
            <RadioGroup.Label sx={{fontSize: '14px', fontWeight: 600}}>OsType</RadioGroup.Label>
            <Box sx={rowStyle}>
              <FormControl>
                <Radio value="Linux" checked={osType === 'Linux'} />
                <FormControl.Label sx={{fontWeight: 400}}>Linux</FormControl.Label>
              </FormControl>
              <FormControl>
                <Radio value="Windows" checked={osType === 'Windows'} />
                <FormControl.Label sx={{fontWeight: 400}}>Windows</FormControl.Label>
              </FormControl>
            </Box>
          </RadioGroup>
          <RadioGroup
            name="architecture"
            onChange={value => setArchitecture(value as Architecture)}
            disabled={isUpdateAction}
          >
            <RadioGroup.Label sx={{fontSize: '14px', fontWeight: 600}}>Architecture</RadioGroup.Label>
            <Box sx={rowStyle}>
              <FormControl>
                <Radio value="X64" checked={architecture === 'X64'} />
                <FormControl.Label sx={{fontWeight: 400}}>X64</FormControl.Label>
              </FormControl>
              <FormControl>
                <Radio value="Arm64" checked={architecture === 'Arm64'} />
                <FormControl.Label sx={{fontWeight: 400}}>Arm64</FormControl.Label>
              </FormControl>
            </Box>
          </RadioGroup>
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
