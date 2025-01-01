import {DatabaseIcon} from '@primer/octicons-react'
import {Box, Label, Text} from '@primer/react'
import {theme} from '../../../theme'

interface Props {
  type: 'telemetry-data' | 'repository-data'
}

export function DataSourceItem({type}: Props) {
  const title = type === 'telemetry-data' ? 'Telemetry data' : 'Repository data'
  const cellText = type === 'telemetry-data' ? 'Excellent' : 'Sufficient'
  const cellVariant = type === 'telemetry-data' ? 'success' : 'accent'
  const space = type === 'telemetry-data' ? '40' : '30'

  return (
    <Box
      sx={{
        alignItems: 'center',
        borderTop: '1px solid var(--borderColor-default)',
        display: 'flex',
        height: '50px',
        justifyContent: 'space-between',
        px: '20px',
        py: '16px',
        width: '100%',
      }}
    >
      <Box sx={{alignItems: 'center', display: 'flex', gap: '8px'}}>
        <Box sx={{color: theme.color.fgMuted}}>
          <DatabaseIcon size={16} />
        </Box>
        <Text sx={{color: theme.color.fgDefault, ...theme.typography.body.smallBold}}>{title}</Text>
      </Box>

      <Box sx={{alignItems: 'center', display: 'flex', gap: '28px'}}>
        <Label variant={cellVariant}>{cellText}</Label>

        <Text sx={{color: theme.color.fgDefault, ...theme.typography.body.small}}>{space} GB / 100 GB</Text>
      </Box>
    </Box>
  )
}
