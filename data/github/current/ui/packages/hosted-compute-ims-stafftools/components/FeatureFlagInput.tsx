import {Box, FormControl, Select, TextInput} from '@primer/react'
import type {ImageDefinitionEnabled} from '../types/types'
import {useState} from 'react'
import {validateFeatureFlag} from '../helpers/utils'

interface FeatureFlagInputProps {
  enabled: ImageDefinitionEnabled
  featureFlag: string
  onEnabledChange: (enabled: ImageDefinitionEnabled) => void
  onFeatureFlagChange: (featureFlag: string) => void
}

export function FeatureFlagInput({enabled, featureFlag, onEnabledChange, onFeatureFlagChange}: FeatureFlagInputProps) {
  const [isFeatureFlagValid, setIsFeatureFlagValid] = useState(true)
  const handleEnabledChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const selectedValue = e.target.value as ImageDefinitionEnabled
    onEnabledChange(selectedValue)
    if (selectedValue !== 'FeatureFlag') {
      onFeatureFlagChange('')
    }
  }

  const handleFeatureFlagChange = (value: string) => {
    setIsFeatureFlagValid(validateFeatureFlag(enabled, value))
    onFeatureFlagChange(value)
  }

  return (
    <div>
      <Box
        sx={{
          width: '30%',
          display: 'inline-block',
        }}
      >
        <FormControl required>
          <FormControl.Label>Enabled</FormControl.Label>
          <Select name="enabled" value={enabled} onChange={handleEnabledChange}>
            <Select.Option value="Enabled">Enabled</Select.Option>
            <Select.Option value="FeatureFlag">Feature Flag</Select.Option>
            <Select.Option value="Disabled">Disabled</Select.Option>
          </Select>
        </FormControl>
      </Box>
      <Box
        sx={{
          width: '70%',
          display: 'inline-block',
        }}
      >
        {enabled === 'FeatureFlag' && (
          <FormControl required>
            <FormControl.Label>Feature Flag</FormControl.Label>
            <TextInput
              name="featureFlag"
              block
              value={featureFlag}
              onChange={e => handleFeatureFlagChange(e.target.value)}
            />
            {!isFeatureFlagValid && (
              <FormControl.Validation variant="error">
                Must start with &quot;ims_&quot; prefix and may contain only letters, numbers and underscores
              </FormControl.Validation>
            )}
          </FormControl>
        )}
      </Box>
    </div>
  )
}
