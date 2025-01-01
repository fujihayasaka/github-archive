import {Box, Text} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {usePipelineDetails} from '../PipelineDetails'
import {isListItemStyle} from './shared'
import {BannerTitle} from './BannerTitle'

interface Props {
  isListItem?: boolean
}

export function InProgressBanner({isListItem = false}: Props) {
  const {adminEmail, hasAnyDeployed} = usePipelineDetails()

  const notificationText = adminEmail
    ? `We'll send an email notification to ${adminEmail} when training is complete.`
    : 'Please revisit this page later to check the status of your training.'
  const deployedText = hasAnyDeployed ? 'Your existing model is still deployed.' : ''
  const text = `${notificationText} ${deployedText}`.trim()

  return (
    <Banner
      description={
        <Box sx={{display: 'flex', flexDirection: 'column', gap: '0.25rem'}}>
          <BannerTitle isListItem={isListItem}>This may take a while.</BannerTitle>
          <Text sx={{wordBreak: 'break-word'}}>{text}</Text>
        </Box>
      }
      style={isListItem ? isListItemStyle : undefined}
      variant="info"
    />
  )
}
