import {AiModelIcon, PlusIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {createElement} from 'react'
import {sendEvent, type SendEventContext} from '../../../utils/send-event'
import {EvaluatorTemplateCategories, type EvaluatorTemplate} from '../evaluator-template'
import {GroupedEvaluatorTemplates} from '../evaluators'
import {AddEvaluatorSelectionClicked} from '../types'

interface AddEvaluatorMenuProps {
  onSelectTemplate: (evalTpl: EvaluatorTemplate) => void
  totalEvaluators: number
}

export function AddEvaluatorMenu({onSelectTemplate, totalEvaluators}: AddEvaluatorMenuProps) {
  return (
    <ActionMenu>
      <ActionMenu.Button leadingVisual={PlusIcon} size="small">
        Add evaluator
      </ActionMenu.Button>
      <ActionMenu.Overlay width="medium">
        <ActionList>
          {Object.entries(GroupedEvaluatorTemplates).map(([category, templates]) => {
            return (
              <ActionList.Group key={category}>
                <ActionList.GroupHeading>{EvaluatorTemplateCategories[category]?.name || ''}</ActionList.GroupHeading>
                {templates.map(et => (
                  <ActionList.Item
                    key={et.displayName}
                    onSelect={() => {
                      onSelectTemplate(et)
                      const payload: SendEventContext = {evaluator: et.displayName, category, totalEvaluators}
                      sendEvent(AddEvaluatorSelectionClicked, payload)
                    }}
                  >
                    <ActionList.LeadingVisual>{createElement(et.icon || AiModelIcon)}</ActionList.LeadingVisual>
                    {et.displayName}
                    <ActionList.Description variant="block">{et.description}</ActionList.Description>
                  </ActionList.Item>
                ))}
              </ActionList.Group>
            )
          })}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
