import {AnimatedList} from './AnimatedList'
import styles from './Layout.module.css'
import {CompactNode} from './nodes/compact/CompactNode'
import type {NodeType as NodeTypeProps} from '../types/app'
import {useLoopLens} from '../hooks/use-loop-lens'

export interface Node {
  title: string
  type: NodeTypeProps
}

/**
 * Use mockData on the initial render—before Copilot responds,
 * because we don’t have any real node data yet.
 */
const mockData: Node[] = [
  {
    title: 'Training the model...',
    type: 'prompt',
  },
  {
    title: 'Parsing your prompts...',
    type: 'prompt',
  },
  {
    title: 'Predicting next step...',
    type: 'prompt',
  },
  {
    title: 'Tokenizing thoughts...',
    type: 'text',
  },
  {
    title: 'Analyzing semantics...',
    type: 'code',
  },
  {
    title: 'Dreaming in code...',
    type: 'code',
  },
  {
    title: 'Activating neural nets...',
    type: 'text',
  },
  {
    title: 'Aligning intents...',
    type: 'prompt',
  },
  {
    title: 'Expanding vocabulary...',
    type: 'text',
  },
  {
    title: 'Crafting solutions...',
    type: 'code',
  },
  {
    title: 'Exploring possibilities...',
    type: 'prompt',
  },
  {
    title: 'Synthesizing context...',
    type: 'text',
  },
  {
    title: 'Optimizing creativity...',
    type: 'text',
  },
  {
    title: 'Chatting with AI...',
    type: 'prompt',
  },
  {
    title: 'Thinking in tokens...',
    type: 'prompt',
  },
  {
    title: 'Generating new ideas...',
    type: 'text',
  },
]

export const LoopPlaceholder = () => {
  const nodes = useLoopLens(
    pipeline =>
      pipeline?.nodes?.map(node => ({
        title: node.title,
        type: node.type,
      })) ?? [],
  )
  const data = nodes && nodes.length > 0 ? nodes : mockData
  const maxVisible = 3
  return (
    <div className={styles.placeholder}>
      <AnimatedList maxVisible={maxVisible} delay={3000}>
        {/*
         *  If the available data has fewer elements than `maxVisible`, the array is
         *  duplicated (flattening `Array.from({ length: maxVisible + 1 }, () => data)`)
         *  so the card animation still has enough items to cycle through.
         *  This guarantees, for example, that with only one node we can still display
         *  three animated cards on the view.
         */}
        {Array.from({length: maxVisible + 1}, () => data)
          .flat()
          .map((item, index) => (
            <CompactNode
              title={item.title}
              type={item.type}
              key={`node-${item.title}-${index}`}
              nodeId={`node-${index}`}
              className={styles.placeholderNode}
              pipelineId="default-pipeline"
            />
          ))}
      </AnimatedList>
      <span className={styles.placeholderText}>Updating your loop...</span>
    </div>
  )
}
