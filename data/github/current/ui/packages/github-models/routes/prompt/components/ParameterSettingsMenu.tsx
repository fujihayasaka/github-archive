import {SlidersIcon} from '@primer/octicons-react'
import {ActionMenu, IconButton, ActionList, Heading, type IconButtonProps} from '@primer/react'
import ModelParameters from '../../playground/components/ModelParametersSidebar/ModelParameters'
import styles from './ParameterSettingsMenu.module.css'
import type {ModelInputChangeParams, ModelState, PlaygroundResponseFormat} from '../../../types'

interface ParametersSettingsMenuProps {
  model: ModelState
  onOpenChange?: (isOpen: boolean) => void
  handleModelParamsChange: ({key, value, validate}: ModelInputChangeParams) => void
  handleSystemPromptChange?: (event: React.ChangeEvent<HTMLTextAreaElement>) => void
  handleResponseFormatChange?: (selectedResponseFormat: PlaygroundResponseFormat) => void
  handleIsUseIndexSelectedChange?: (isSelected: boolean) => void
  handleJsonSchemaChange?: (jsonSchema: string) => void
  updateSystemPrompt?: (systemPrompt: string) => void
  iconSize?: 'small' | 'medium'
  className?: string
  children?: React.ReactNode
}

export default function ParameterSettingsMenu({
  model,
  onOpenChange,
  handleModelParamsChange,
  handleSystemPromptChange,
  handleResponseFormatChange,
  handleIsUseIndexSelectedChange,
  handleJsonSchemaChange,
  updateSystemPrompt,
  iconSize = 'small',
  className = '',
  children,
}: ParametersSettingsMenuProps) {
  const disabledProps: Pick<IconButtonProps, 'onClick' | 'aria-disabled'> = !model.catalogData
    ? {'aria-disabled': true, onClick: e => e.preventDefault()}
    : {}

  return (
    <ActionMenu onOpenChange={onOpenChange}>
      <ActionMenu.Anchor>
        <IconButton
          icon={SlidersIcon}
          size={iconSize}
          aria-label="Show parameters setting"
          className={className}
          {...disabledProps}
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="xlarge" side="outside-left">
        <ActionList>
          <div
            className="d-flex flex-items-center border-bottom borderColor-default px-3 py-2"
            style={{minHeight: '49px'}} // This is to prevent the height from changing when the reset button appears
          >
            <Heading as="h1" className={styles.parametersHeading}>
              Parameters
            </Heading>
            {children}
          </div>
          <ModelParameters
            model={model}
            handleModelParamsChange={handleModelParamsChange}
            handleSystemPromptChange={handleSystemPromptChange}
            handleResponseFormatChange={handleResponseFormatChange}
            handleIsUseIndexSelectedChange={handleIsUseIndexSelectedChange}
            handleJsonSchemaChange={handleJsonSchemaChange}
            updateSystemPrompt={updateSystemPrompt}
          />
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
