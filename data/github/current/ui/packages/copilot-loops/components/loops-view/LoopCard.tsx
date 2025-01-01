import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {Card} from '@github-ui/pacer/Card'
import {NodeIcon} from '@github-ui/pacer/CustomIcon'
import type {Pipeline} from '../../types/app'
import {LoopsActionMenu} from '../controls/LoopsActionMenu'
import {availableColors, pickColorBasedOnString} from '../../utils/color'

export interface LoopCardProps {
  item: Pipeline
  onClick?: () => void
}

export function LoopCard({item, onClick}: LoopCardProps) {
  const color = availableColors.find(c => c === item.color)
  return (
    <Card key={item.id} href={`${COPILOT_PATH}/l/${item.id}`} onClick={onClick}>
      <Card.Icon icon="loops" color={color ?? pickColorBasedOnString(item.title, availableColors)} />
      <Card.Heading>{item.title}</Card.Heading>
      <Card.Description>{item.description}</Card.Description>
      <Card.Metadata>
        <NodeIcon />
        {item.nodes.length}
      </Card.Metadata>
      <Card.Menu>
        <LoopsActionMenu loopId={item.id} />
      </Card.Menu>
    </Card>
  )
}
