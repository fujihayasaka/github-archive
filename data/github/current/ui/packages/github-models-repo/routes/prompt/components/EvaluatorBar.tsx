import {AiModelIcon, PlusIcon, SparkleFillIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Token} from '@primer/react'
import React, {useCallback, useState} from 'react'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import type {EvaluatorCfg} from '../evals-sdk/config'
import {EvaluatorTemplateCategories, type EvaluatorTemplate} from '../evaluator-template'
import {GroupedEvaluatorTemplates} from '../evaluators'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {EvaluatorDialog} from './evaluators/EvaluatorDialog'

export function EvaluatorBar() {
  const {compare} = usePromptCompareState()
  const {evaluators} = compare

  const manager = usePromptCompareManager()

  const [addEvaluatorTemplate, setAddEvaluatorTemplate] = useState<EvaluatorTemplate | undefined>(undefined)
  const [editEvaluatorIndex, setEditEvaluatorIndex] = useState<number | undefined>(undefined)
  const [editEvaluator, setEditEvaluator] = useState<EvaluatorCfg | undefined>(undefined)
  const [evaluatorDialogOpen, setEvaluatorDialogOpen] = useState(false)

  const handleEvalAdd = useCallback(
    (et: EvaluatorTemplate) => {
      if (et.readonly) {
        // Template cannot be customized, add directly
        manager.evalsAddEvaluator({
          config: et.configTemplate,
          readonly: true,
        })
        return
      }

      setAddEvaluatorTemplate(et)
      setEvaluatorDialogOpen(true)
    },
    [setAddEvaluatorTemplate, setEvaluatorDialogOpen, manager],
  )

  const handleEvalEdit = useCallback(
    (index: number, e: EvaluatorCfg) => {
      setEditEvaluatorIndex(index)
      setEditEvaluator(e)
      setEvaluatorDialogOpen(true)
    },
    [setEditEvaluatorIndex, setEditEvaluator, setEvaluatorDialogOpen],
  )

  const handleEvalRemove = useCallback(
    (index: number) => {
      manager.evalsRemoveEvaluator(index)
    },
    [manager],
  )

  return (
    <>
      {evaluatorDialogOpen && (
        <EvaluatorDialog
          template={addEvaluatorTemplate}
          evaluatorIndex={editEvaluatorIndex}
          evaluator={editEvaluator}
          onClose={() => {
            setAddEvaluatorTemplate(undefined)
            setEditEvaluator(undefined)
            setEvaluatorDialogOpen(false)
          }}
        />
      )}

      <div className="d-flex flex-wrap border-bottom flex-items-center px-2 pt-2">
        {evaluators.map((e, index) => (
          <Token
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={`evaluator-${e.config.name}-${index}`}
            className="mr-2 mb-2"
            as="button"
            leadingVisual={SparkleFillIcon}
            text={e.config.name}
            size="large"
            onClick={() => handleEvalEdit(index, e.config)}
            onRemove={() => handleEvalRemove(index)}
          />
        ))}

        <ActionMenu>
          <ActionMenu.Anchor>
            <Token className="mb-2" leadingVisual={PlusIcon} as="button" text="Add evaluator" size="large" />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay width="medium">
            <ActionList>
              {Object.entries(GroupedEvaluatorTemplates).map(([category, templates]) => {
                return (
                  <ActionList.Group key={category}>
                    <ActionList.GroupHeading>
                      {EvaluatorTemplateCategories[category]?.name || ''}
                    </ActionList.GroupHeading>
                    {templates.map(et => (
                      <ActionList.Item key={et.displayName} onSelect={() => handleEvalAdd(et)}>
                        <ActionList.LeadingVisual>
                          {React.createElement(et.icon || AiModelIcon)}
                        </ActionList.LeadingVisual>
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
      </div>
    </>
  )
}
