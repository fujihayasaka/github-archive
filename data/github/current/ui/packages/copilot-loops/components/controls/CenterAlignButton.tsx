import {IconButton} from '@primer/react'
import {FocusCenterIcon} from '../CustomIcon'

interface CenterAlignButtonProps {
  onClick: (e: React.MouseEvent<HTMLButtonElement>) => void
}

export function CenterAlignButton({onClick}: CenterAlignButtonProps) {
  return <IconButton aria-label={'Set center alignment'} icon={FocusCenterIcon} onClick={e => onClick(e)} />
}
