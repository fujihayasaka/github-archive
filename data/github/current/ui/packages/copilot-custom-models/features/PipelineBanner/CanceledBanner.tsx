import {Box, Link, Text} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useNavigateWithFlashBanner} from '../NavigateWithFlashBanner'
import {usePipelineDetails} from '../PipelineDetails'
import {isListItemStyle} from './shared'
import {BannerTitle} from './BannerTitle'
import {format} from 'date-fns'

interface Props {
  isListItem?: boolean
}

export function CanceledBanner({isListItem = false}: Props) {
  const {
    hasAnyDeployed,
    bannerPipeline: {canRetrain, editPath},
    rateLimitResetAt,
  } = usePipelineDetails()
  const {navigate} = useNavigateWithFlashBanner()

  const resetAtText = rateLimitResetAt
    ? `Please try again after ${formatResetAt(rateLimitResetAt)}.`
    : 'Please try again later.'

  const nextStep = canRetrain ? (
    <>
      Please contact support for help or{' '}
      <Link href="#" inline onClick={() => navigate(editPath)} sx={{cursor: 'pointer'}}>
        try again
      </Link>
      .
    </>
  ) : (
    `You cannot start a new training session because you've reached the limit of one training per week. ${resetAtText} If you need further assistance, please contact support.`
  )
  const deployedText = hasAnyDeployed ? 'Your existing model is still deployed.' : ''

  return (
    <Banner
      description={
        <Box sx={{display: 'flex', flexDirection: 'column', gap: '0.25rem'}}>
          <BannerTitle isListItem={isListItem}>Training run was canceled.</BannerTitle>
          <Text sx={{wordBreak: 'break-word'}}>
            {nextStep} {deployedText}
          </Text>
        </Box>
      }
      style={isListItem ? isListItemStyle : undefined}
      variant="warning"
    />
  )
}

function formatResetAt(resetAt: string | null): string {
  if (!resetAt) return ''

  return format(new Date(resetAt).toLocaleString(), 'MMMM do')
}
