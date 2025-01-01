import {colorNames, useNamedColor} from '@github-ui/use-named-color'
import {Box} from '@primer/react'

type IssueTypeDotProps = {color: string}

export const IssueTypeDot = ({color}: IssueTypeDotProps) => {
  const effectiveColor = colorNames.find(c => c === color)
  const {fg} = useNamedColor(effectiveColor)

  return (
    <Box
      sx={{
        width: 8,
        height: 8,
        borderRadius: 100,
        boxShadow: '0 0 0 2px var(--bgColor-muted, var(--color-canvas-subtle))',
        backgroundColor: `${fg}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    />
  )
}
