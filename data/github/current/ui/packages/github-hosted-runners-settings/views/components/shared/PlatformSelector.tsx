import {Box, Button, FormControl, Radio, RadioGroup} from '@primer/react'
import {useState, type ChangeEvent} from 'react'
import type {FieldProgressionFieldEditComponentProps} from './FieldProgressionField'
import {type Platform, platformOptions} from '../../../types/platform'
import {PlatformIcon} from './PlatformIcon'
import type {MachineSpec} from '../../../types/machine-spec'
import type {Image} from '../../../types/image'

interface IProps extends FieldProgressionFieldEditComponentProps<Platform> {
  isCustomImageUploadingEnabled: boolean
  machineSpecs: MachineSpec[]
  images: {[key: string]: Image[]}
  onValidationError: (error: boolean) => void
}

export function PlatformSelector(props: IProps) {
  const [editorValue, setEditorValue] = useState<Platform | null>(props.value || platformOptions[0] || null)

  const handleInputChange = (selected: string | null, e: React.ChangeEvent<HTMLInputElement> | undefined) => {
    if (e) {
      const selectedPlatform = platformOptions.find(option => option.id === selected)
      setEditorValue(selectedPlatform || null)
    }
  }

  const handleSave = () => {
    props.onValidationError(false)
    if (!editorValue) {
      props.onValidationError(true)
      return
    }

    props.setValue(editorValue)
    if (props.onSave) {
      props.onSave()
    }
  }

  const availableOptions = platformOptions.filter(option => {
    const isCustomPlatform = option.id === 'custom'

    return props.isCustomImageUploadingEnabled || !isCustomPlatform
  })

  return (
    <>
      <Box sx={{m: 3, mt: 2}} data-testid="platform-input">
        <RadioGroup
          name={'platformRadioGroup'}
          onChange={(selected, e: ChangeEvent<HTMLInputElement> | undefined) => {
            handleInputChange(selected, e)
          }}
        >
          <RadioGroup.Label visuallyHidden>Platform</RadioGroup.Label>
          {availableOptions.map(option => (
            <FormControl key={option.id}>
              <Radio
                value={option.id}
                checked={option === editorValue}
                data-testid={`platform-option-radio-${option.id}`}
              />
              <FormControl.Label sx={{fontWeight: 'normal'}} data-testid={`platform-option-label-${option.id}`}>
                <PlatformIcon osType={option.osType} className="mr-2 color-fg-muted" />
                {option.displayName}
              </FormControl.Label>
            </FormControl>
          ))}
        </RadioGroup>
      </Box>
      <Box sx={{borderTopColor: 'border.default', borderTopStyle: 'solid', borderTopWidth: 1}}>
        <Button sx={{m: 3, mb: 0}} onClick={handleSave} data-testid="platform-save-button">
          Save
        </Button>
      </Box>
    </>
  )
}
