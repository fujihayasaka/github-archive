import {useCallback, useState} from 'react'
import type {Node, TextNode} from '../../types/app'
import {clearDownstreamNodes, getOutputNodes, sanitizeNode} from '../../utils/pipes'
import {removeCodeBlock} from '../../utils/string'
import {logError} from '../../utils/console'
import {isCodeNode} from '../../utils/node-assertions'
import {PillBoxNode} from './pillbox/PillBoxNode'
import {CompactStyle} from './compact/CompactStyle'
import {DashboardStyle} from './dashboard/DashboardStyle'
import {useGetPipesState, usePipesDispatch} from '../../contexts/PipesStateProvider'
import {useCurrentPipeline, useNode} from '../../state/lenses'
import {usePipesService} from '../../contexts/PipesServiceProvider'
import {useDebounce} from '@github-ui/use-debounce'

type NodeComponentStyle = 'pillbox' | 'card' | 'dashboard' | 'just-output' | 'compact'
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const JustOutputStyle = (_props: any) => <div>JustOutputStyle</div>

interface NodeComponentProps {
  pipelineId: string
  nodeId: string
  className?: string
  style?: NodeComponentStyle
  isSelected?: boolean
  isContentVisibleDefault?: boolean
}

export const NodeComponent: React.FC<NodeComponentProps> = ({
  pipelineId,
  nodeId,
  className,
  style = 'pillbox',
  isSelected,
  isContentVisibleDefault = false,
}) => {
  return (
    <NodeComponentInner
      pipelineId={pipelineId}
      nodeId={nodeId}
      className={className}
      style={style}
      isSelected={isSelected}
      isContentVisibleDefault={isContentVisibleDefault}
    />
  )
}

const NodeComponentInner = ({
  pipelineId,
  nodeId,
  className,
  style,
  isSelected,
  isContentVisibleDefault = false,
}: {
  pipelineId: string
  nodeId: string
  className?: string
  style?: NodeComponentStyle
  isSelected?: boolean
  isContentVisibleDefault?: boolean
}) => {
  const dispatch = usePipesDispatch()
  const service = usePipesService()
  const getState = useGetPipesState()

  const node = useNode(nodeId)
  const pipeline = useCurrentPipeline()

  const isOutput = getOutputNodes(pipeline).some(n => n.id === nodeId)
  const isExpandedByDefault = !!(node as TextNode).inputType || isOutput

  const [isCollapsed, setIsCollapsed] = useState(!isExpandedByDefault)
  const [isContentVisible, setIsContentVisible] = useState<boolean>(isContentVisibleDefault)

  const runPipelineFromThisNode = useDebounce(() => {
    const currentIteration = getState().executionState.iteration
    service.runPipeline(pipeline, currentIteration, dispatch)
  }, 1000)

  const handleNodeUpdate = async () => {
    if (getState().pipelineState.validationErrors.length > 0) return
    if (!node) return

    try {
      dispatch({type: 'INCREMENT_ITERATION'})
      clearDownstreamNodes(pipeline, node.id, dispatch)
      runPipelineFromThisNode()
    } catch (error) {
      logError('Error updating node:', error)
    }
  }

  const handleUpdate = (updates: Partial<Node>) => {
    if (!node) return
    if (isCodeNode(node) && updates.content) {
      updates.content = removeCodeBlock(updates.content)
    }

    const pipelines = getState().pipelineState.pipelines
    const sanitizedNode = sanitizeNode({...node, ...updates} as Node, Object.values(pipelines))
    if (!sanitizedNode) return

    dispatch({
      type: 'UPDATE_NODE',
      pipelineId,
      nodeId: node.id,
      updates: {
        ...sanitizedNode,
      },
    })

    if (getState().pipelineState.validationErrors.length > 0) return

    dispatch({type: 'INCREMENT_ITERATION'})
    clearDownstreamNodes(pipeline, node.id, dispatch)
    runPipelineFromThisNode()
  }

  const handleStop = useCallback(() => {
    const iteration = getState().executionState.iteration
    dispatch({type: 'CANCEL_EXECUTION', iteration})
  }, [dispatch, getState])

  if (!node) return null

  switch (style) {
    case 'pillbox':
      return (
        <PillBoxNode
          nodeId={node.id}
          pipelineId={pipelineId}
          isCollapsed={isCollapsed}
          isContentVisible={isContentVisible}
          className={className}
          onToggleExpand={setIsCollapsed}
          onNodeUpdate={handleNodeUpdate}
          onUpdate={handleUpdate}
          onStop={handleStop}
          onToggleContent={() => setIsContentVisible(prev => !prev)}
          isOutput={isOutput}
        />
      )
    case 'dashboard':
      return (
        <DashboardStyle
          nodeId={node.id}
          pipelineId={pipelineId}
          isContentVisible={isContentVisible ?? false}
          className={className}
          onNodeUpdate={handleNodeUpdate}
          onUpdate={handleUpdate}
          onStop={handleStop}
          setIsContentVisible={setIsContentVisible}
          isOutput={isOutput}
          onToggleContent={() => setIsContentVisible(prev => !prev)}
        />
      )
    case 'just-output':
      return (
        <JustOutputStyle
          nodeId={node.id}
          pipelineId={pipelineId}
          isContentVisible={isContentVisible ?? false}
          isOutput={isOutput}
          handleNodeUpdate={handleNodeUpdate}
          handleUpdate={handleUpdate}
          handleStop={handleStop}
          setIsContentVisible={setIsContentVisible}
        />
      )
    case 'compact':
      return (
        <CompactStyle
          nodeId={node.id}
          pipelineId={pipelineId}
          className={className}
          isSelected={isSelected ?? false}
          // TODO: need to bring those func back
          // isContentVisible={isContentVisible}
          // onToggleExpand={onToggleExpand}
          // handleNodeUpdate={handleNodeUpdate}
          // handleUpdate={handleUpdate}
          // handleStop={handleStop}
          // setIsContentVisible={setIsContentVisible}
          // isOutput={isOutput}
        />
      )
    default:
      return null
  }
}
