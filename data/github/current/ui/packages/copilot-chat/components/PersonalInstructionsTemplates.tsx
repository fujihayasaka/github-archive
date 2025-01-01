import {LightBulbIcon, PlusIcon, XIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {forwardRef, type RefObject, useState} from 'react'

import {suggestedPersonalInstructions} from '../utils/custom-instructions'

export interface TemplateProps {
  onSelect: (key: string, value: string | undefined) => void
}
export type Ref = HTMLDivElement | null

export const PersonalInstructionsTemplates = forwardRef<Ref, TemplateProps>(
  function PersonalInstructionsTemplatesWithRef(props, ref) {
    const {onSelect} = props
    const [showTemplates, setShowTemplates] = useState<boolean>(false)
    const toggleShowTemplates = () => setShowTemplates(!showTemplates)

    return (
      <div
        ref={ref as RefObject<HTMLDivElement>}
        className="d-inline-flex flex-justify-between position-absolute bgColor-default right-0 left-0 bottom-0 ml-2 mr-3"
        style={{marginBottom: '1px'}}
      >
        <ActionList className={'d-inline-flex flex-wrap gap-2 rounded-2'}>
          {showTemplates &&
            Object.entries(suggestedPersonalInstructions)?.map(([key, value]) => (
              <ActionList.Item
                aria-label={`${value.tooltip}`}
                className={`mx-0 border fgColor-muted d-inline-block width-auto`}
                key={key}
                onSelect={() => onSelect(key, value.body)}
              >
                <PlusIcon />
                {key}
              </ActionList.Item>
            ))}
        </ActionList>
        <ActionList className="d-flex flex-column flex-justify-end">
          <ActionList.Item
            aria-label={showTemplates ? 'Hide templates' : 'Show templates'}
            data-testid="toggle-templates"
            className={`fgColor-muted d-inline-block width-auto flex-justify-end mx-0`}
            style={{border: '1px solid transparent'}} // To prevent height change as light bulb icon is smaller than X icon
            onSelect={toggleShowTemplates}
          >
            {showTemplates ? <XIcon /> : <LightBulbIcon />}
          </ActionList.Item>
        </ActionList>
      </div>
    )
  },
)
