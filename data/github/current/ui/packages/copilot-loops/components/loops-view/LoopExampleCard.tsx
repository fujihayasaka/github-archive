import {Card} from '@github-ui/pacer/Card'
import {NodeIcon} from '@github-ui/pacer/CustomIcon'
import type {Pipeline} from '../../types/app'
import {sendEvent} from '@github-ui/hydro-analytics'

export interface LoopExampleCardProps {
  altText: string
  assetPath: string
  exampleLoop: Pick<Pipeline, 'title' | 'description' | 'nodes'>
  onSelect: (loop: Pipeline) => void
}

export function LoopExampleCard({altText, assetPath, exampleLoop, onSelect}: LoopExampleCardProps) {
  const handleClick = () => {
    sendEvent('dotcom_chat.activate', {target: 'OVERVIEW_EXAMPLE_LOOP_SELECT', mode: 'loops'})
    const newLoop = {
      ...exampleLoop,
      id: crypto.randomUUID(),
      updatedAt: new Date().toISOString(),
    } as Pipeline

    onSelect(newLoop)
  }

  return (
    <Card key={exampleLoop.title} onClick={handleClick}>
      <Card.Image alt={altText} img={assetPath} />
      <Card.Heading>{exampleLoop.title}</Card.Heading>
      <Card.Description>{exampleLoop.description}</Card.Description>
      <Card.Metadata>
        <NodeIcon />
        {exampleLoop.nodes.length}
      </Card.Metadata>
    </Card>
  )
}
