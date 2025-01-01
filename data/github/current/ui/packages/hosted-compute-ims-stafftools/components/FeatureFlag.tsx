import {Box, FormControl, Select, TextInput} from '@primer/react'
import type {ImageDefinitionEnabled} from '../types/types'
import {rowStyle} from '../helpers/style'
import {Constants} from '../helpers/constants'
import {useState} from 'react'
import {validateFeatureFlag} from '../helpers/utils'

interface FeatureFlagProps {
  enabled: ImageDefinitionEnabled
  featureFlag: string
  onEnabledChange: (enabled: ImageDefinitionEnabled) => void
  onFeatureFlagChange: (featureFlag: string) => void
}

export function FeatureFlag({enabled, featureFlag, onEnabledChange, onFeatureFlagChange}: FeatureFlagProps) {
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
      <Box sx={rowStyle}>
        <FormControl required>
          <FormControl.Label>Enabled</FormControl.Label>
          <Select name="enabled" value={enabled} onChange={handleEnabledChange}>
            <Select.Option value="Enabled">Enabled</Select.Option>
            <Select.Option value="FeatureFlag">Feature Flag</Select.Option>
            <Select.Option value="Disabled">Disabled</Select.Option>
          </Select>
        </FormControl>
        {enabled === 'FeatureFlag' && (
          <FormControl required>
            <FormControl.Label>Feature Flag</FormControl.Label>
            <TextInput name="featureFlag" value={featureFlag} onChange={e => handleFeatureFlagChange(e.target.value)} />
          </FormControl>
        )}
      </Box>
      {enabled === 'FeatureFlag' && !isFeatureFlagValid && (
        <FormControl sx={{mt: '4px'}}>
          <FormControl.Validation variant="error">{Constants.featureFlagValidation}</FormControl.Validation>
        </FormControl>
      )}
    </div>
  )
}
