import {useCurrentPipeline} from '../../state/lenses'
import type {Node} from '../../types/app'
import {getPipelineGraph} from '../../utils/pipes'
import {NodeComponent} from '../nodes/NodeComponent'
import styles from './BasicView.module.css'

export function BasicView() {
  const pipeline = useCurrentPipeline()
  const graph = getPipelineGraph(pipeline)
  return (
    <div className={styles.container}>
      {graph.layers.map((layer: Node[]) => {
        return layer.map((node: Node) => <NodeComponent key={node.id} pipelineId={pipeline.id} nodeId={node.id} />)
      })}
    </div>
  )
}
