import {Box, type BetterSystemStyleObject} from '@primer/react'

interface Props {
  color: string
  sx?: BetterSystemStyleObject
}

export default function ColoredBullet(props: Props) {
  return <Box sx={{borderRadius: '100px', width: '8px', height: '8px', backgroundColor: props.color, ...props.sx}} />
}
