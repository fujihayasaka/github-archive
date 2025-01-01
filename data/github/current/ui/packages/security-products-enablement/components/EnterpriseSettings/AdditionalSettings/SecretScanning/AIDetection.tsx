import {useState, type MouseEvent} from 'react'

import {ControlGroup} from '@github-ui/control-group'
import {useAppContext} from '../../../../contexts/AppContext'
import {updateAIDetection} from '../../../../utils/api-helpers'
import Validation from '../../../Validation'

export interface AIDetectionProps {
  value: null | boolean
}

const AIDetection: React.FC<AIDetectionProps> = ({value}) => {
  const {enterprise} = useAppContext()
  const enterpriseSlug = enterprise!.slug
  const [aiDetection, setAIDetection] = useState(value)
  const [error, setError] = useState<string | null>(null)

  const handleClick = async (e: MouseEvent<HTMLButtonElement>) => {
    e.preventDefault()

    const newValue = !aiDetection
    const resp = await updateAIDetection(enterpriseSlug, {
      secret_scanning_generic_secrets: newValue ? 'enabled' : 'disabled',
    })

    if (resp && resp.success === true) {
      setAIDetection(newValue)
      setError(null)
    } else {
      if (resp && resp.error_message) {
        setError(resp.error_message)
      } else {
        setError('Something went wrong, please try again.')
      }
    }
  }

  return (
    aiDetection !== null && (
      <ControlGroup.Item>
        <ControlGroup.Title id="ai-detection">Use AI detection to find additional secrets</ControlGroup.Title>
        <ControlGroup.Description>
          Use an AI model to detect additional secrets beyond the secrets detected with regular expressions.
          {error && <Validation validationStatus="error">{error}</Validation>}
        </ControlGroup.Description>
        <ControlGroup.ToggleSwitch
          data-testid="ai-detection-toggle"
          aria-labelledby="ai-detection-toggle"
          checked={aiDetection}
          onClick={handleClick}
        />
      </ControlGroup.Item>
    )
  )
}

export default AIDetection
