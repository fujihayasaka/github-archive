import type {Node} from '../../types/app'
import {NodeInput} from './NodeInput'
import styles from './NodeContent.module.css'
import {clsx} from 'clsx'
import {ContentEditor} from '../controls/ContentEditor'
import {useCallback, useState} from 'react'
import {Button} from '@primer/react'
import {useFocusWithin} from '../../hooks/use-focus-within'
import {useNodeContent, useNodeType} from '../../state/lenses'

interface NodeContentProps {
  nodeId: string
  pipelineId: string
  isContentVisible: boolean
  isCollapsed: boolean
  isLoading: boolean
  onUpdate: (updates: Partial<Node>) => void
  onToggleContent: () => void
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const PipelineContent = (_props: any) => null
// const PipelineContent = ({node, pipelineId, onUpdate}: NodeContentProps & {node: PipelineNode}) => (
//   <>
//     <PipelinePicker
//       value={node.pipelineId}
//       onChange={newValue => {
//         onUpdate({pipelineId: newValue})
//       }}
//     />
//     <div className="pb-6 px-5">
//       <NodePipelineControl
//         pipelineId={pipelineId || ''}
//         pickedPipelineId={node.pipelineId}
//         node={node}
//         inputValues={node.pipelineInputValues || []}
//         onInputValuesChange={newValue => {
//           onUpdate({
//             pipelineInputValues: newValue,
//             inputs: newValue.map(v => ({id: v.nodeId})),
//           })
//         }}
//       />
//     </div>
//   </>
// )

const DefaultContent = ({nodeId, isContentVisible, onToggleContent, onUpdate}: NodeContentProps) => {
  const nodeContent = useNodeContent(nodeId)
  const [content, setContent] = useState(nodeContent)

  const handleBlur = useCallback(() => isContentVisible && onToggleContent(), [isContentVisible, onToggleContent])
  const handleFocus = useCallback(() => !isContentVisible && onToggleContent(), [isContentVisible, onToggleContent])

  const {ref} = useFocusWithin<HTMLDivElement>({onBlur: handleBlur, onFocus: handleFocus})

  return (
    <div ref={ref} className={styles.container}>
      {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events */}
      <div
        className={clsx(styles.previewContent, isContentVisible ? styles.expanded : styles.collapsed)}
        onClick={!isContentVisible ? onToggleContent : undefined}
      >
        <div className={clsx(styles.previewOverlay, !isContentVisible && styles.visible)} />
        <ContentEditor content={content} onUpdate={newValue => setContent(newValue)} />
        <span className={styles.actions}>
          <Button
            onClick={() => {
              onToggleContent()
              setContent(nodeContent)
            }}
          >
            Cancel
          </Button>
          <Button
            onClick={() => {
              onToggleContent()
              onUpdate({content})
            }}
            variant="primary"
          >
            Save
          </Button>
        </span>
      </div>
    </div>
  )
}

export const NodeContent = (props: NodeContentProps) => {
  const {nodeId, onUpdate} = props
  const type = useNodeType(nodeId)

  let contentNode: JSX.Element
  switch (type) {
    case 'text':
      contentNode = (
        <NodeInput
          nodeId={nodeId}
          onChange={newValue => {
            onUpdate({content: newValue})
          }}
          className={styles.nodeInput}
        />
      )
      break
    case 'pipeline':
      contentNode = <PipelineContent {...props} />
      break
    default:
      contentNode = <DefaultContent {...props} />
      break
  }

  return <div className={styles.nodeContent}>{contentNode}</div>
}
