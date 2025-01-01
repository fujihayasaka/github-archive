import {RocketIcon} from '@primer/octicons-react'
import {Box, CircleBadge, Text} from '@primer/react'
import {BorderBox} from '../../components/BorderBox'
import {usePipelineDetails} from '../PipelineDetails'
import {format} from 'date-fns'
import styles from './SuccessBanner.module.css'

export function SuccessBanner() {
  const {org, rateLimitResetAt} = usePipelineDetails()

  const resetAtText = rateLimitResetAt ? formatResetAt(rateLimitResetAt) : 'one week'

  return (
    <BorderBox
      sx={{
        backgroundColor: 'transparent',
        columnGap: '16px',
        display: 'grid',
        gridTemplateAreas: `'visual message'`,
        gridTemplateColumns: 'min-content 1fr',
        gridTemplateRows: 'min-content',
      }}
    >
      <Box
        sx={{
          alignSelf: 'start',
          display: 'grid',
          gridArea: 'visual',
          paddingBlock: 'var(--base-size-8)',
        }}
      >
        <CircleBadge size={32} sx={{backgroundColor: 'var(--bgColor-done-muted)'}}>
          <CircleBadge.Icon icon={RocketIcon} className={styles.CircleBadge_Icon} />
        </CircleBadge>
      </Box>
      <Box
        sx={{
          alignSelf: 'center',
          display: 'flex',
          flexDirection: 'column',
          fontSize: 1,
          gap: '4px',
          gridArea: 'message',
          lineHeight: '1.5',
        }}
      >
        <Text sx={{fontSize: '16px', fontWeight: 'semibold', lineHeight: '24px'}}>
          {org} model has been successfully deployed.
        </Text>
        <Text sx={{color: 'var(--fgColor-muted)', wordBreak: 'break-word'}}>
          Congratulations! Your custom model has been successfully trained and deployed. Your team can now start using
          it in your IDE. Please note that you can retrain your model after {resetAtText}.
        </Text>
      </Box>
    </BorderBox>
  )
}

function formatResetAt(resetAt: string | null): string {
  if (!resetAt) return ''

  return format(new Date(resetAt).toLocaleString(), 'MMMM do')
}
