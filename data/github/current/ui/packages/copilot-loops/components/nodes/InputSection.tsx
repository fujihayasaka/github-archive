import {useId} from 'react'
import styles from './InputSection.module.css'
import type {Node} from '../../types/app'
import {useNodeContent, useNode} from '../../state/lenses'
import {ModelPicker} from '../controls/ModelPicker'
import {generateDefaultModel} from '@github-ui/copilot-chat/utils/models'
import {ContentEditorWithAutocomplete} from '../controls/ContentEditorWithAutocomplete'
import {GraphQLContentEditor} from '../controls/GraphQLContentEditor'
import {NodeInput} from './NodeInput'
import {InputSectionLayout} from './InputSectionLayout'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

interface InputSectionProps {
  nodeId: string
  pipelineId: string
  isContentVisible: boolean
  isCollapsed: boolean
  isLoading: boolean
  onUpdate: (updates: Partial<Node>) => void
  onToggleContent?: () => void
}

export function InputSection({nodeId, onUpdate}: InputSectionProps) {
  const featureFlags = useFeatureFlags()
  const node = useNode(nodeId)
  const nodeContent = useNodeContent(nodeId)
  const inputLabelId = useId()

  if (!node) return null

  switch (node.type) {
    case 'loop':
      return null

    case 'github-graphql': {
      const contentEditor = (
        <GraphQLContentEditor
          content={nodeContent}
          inputLabelId={inputLabelId}
          nodeId={nodeId}
          onUpdate={newValue => onUpdate({content: newValue})}
        />
      )

      return <InputSectionLayout content={nodeContent} contentEditor={contentEditor} inputLabelId={inputLabelId} />
    }

    case 'text': {
      const contentEditor = (
        <NodeInput
          className={styles.nodeInput}
          content={nodeContent}
          inputLabelId={inputLabelId}
          nodeId={nodeId}
          onChange={newValue => onUpdate({content: newValue})}
        />
      )

      return <InputSectionLayout content={nodeContent} contentEditor={contentEditor} inputLabelId={inputLabelId} />
    }

    case 'prompt': {
      const defaultModel: string = generateDefaultModel().id

      const additionalFields = featureFlags['copilot_loops_post_staff_ship_features'] ? (
        <div className={styles.nodeModel}>
          <div className={styles.groupTitle}>Model</div>
          <div>
            <ModelPicker
              selectedModelName={node.model ?? defaultModel}
              onUpdateModel={(model: string) => onUpdate({...node, model})}
            />
          </div>
        </div>
      ) : null

      const contentEditor = (
        <ContentEditorWithAutocomplete
          content={nodeContent}
          onUpdate={newValue => onUpdate({content: newValue})}
          nodeId={nodeId}
          inputLabelId={inputLabelId}
        />
      )

      return (
        <InputSectionLayout
          additionalFields={additionalFields}
          content={nodeContent}
          contentEditor={contentEditor}
          inputLabelId={inputLabelId}
        />
      )
    }

    default:
      return null
  }
}
