import type {Model} from '@github-ui/marketplace-common'
import {SlidersIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Heading, IconButton} from '@primer/react'
import {useModelDetailsQuery} from '../hooks/use-model-details-query'
import styles from './ParameterSettingsMenu.module.css'
import {PlaygroundInput} from '@github-ui/github-models/PlaygroundInput'
import type {ModelInputChangeParams, ModelParameterValue} from '@github-ui/github-models'

interface ParametersSettingsMenuProps {
  model: Model | undefined
  modelParameters: Record<string, unknown>
  handleModelParamsChange: ({key, value, validate}: ModelInputChangeParams) => void
  className?: string
  iconSize?: 'small' | 'medium'
}

export default function ParameterSettingsMenu({
  model,
  modelParameters,
  handleModelParamsChange,
  iconSize = 'small',
  className = '',
}: ParametersSettingsMenuProps) {
  const {isLoading, data: modelDetails} = useModelDetailsQuery(model?.registry, model?.name)

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton
          icon={SlidersIcon}
          size={iconSize}
          aria-label="Show parameters setting"
          className={className}
          disabled={!model}
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="xlarge" side="outside-left">
        {isLoading && <div>Loading...</div>}
        {!isLoading && modelDetails && (
          <ActionList>
            <div
              className="d-flex flex-items-center border-bottom borderColor-default px-3 py-2"
              style={{minHeight: '49px'}} // This is to prevent the height from changing when the reset button appears
            >
              <Heading as="h1" className={styles.parametersHeading}>
                Parameters
              </Heading>
            </div>
            <div className="px-3 py-2">
              {(modelDetails?.modelInputSchema?.parameters || []).map(parameter => (
                <PlaygroundInput
                  key={parameter.key}
                  value={(modelParameters?.[parameter.key] as ModelParameterValue) ?? ''}
                  parameter={parameter}
                  handleInputChange={handleModelParamsChange}
                />
              ))}
            </div>
          </ActionList>
        )}
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
