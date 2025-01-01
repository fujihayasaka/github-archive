import {Banner} from '@primer/react/experimental'
import {useNavigateWithFlashBanner} from '../NavigateWithFlashBanner'
import {usePipelineDetails} from '../PipelineDetails'
import {isListItemStyle} from './shared'
import {Box, Text} from '@primer/react'
import {BannerTitle} from './BannerTitle'

interface Props {
  isListItem?: boolean
}

export function FailedBanner({isListItem = false}: Props) {
  const {
    canViewDetails,
    bannerPipeline: {canRetrain, editPath, showPath},
    hasAnyDeployed,
    org,
  } = usePipelineDetails()
  const {navigate} = useNavigateWithFlashBanner()

  const handleRetrainClick = () => navigate(editPath)

  let text

  if (hasAnyDeployed && canRetrain) {
    text =
      'Your previous model is still deployed. Your team can now still use the previous model in their IDE. Please review the recent training run or try retraining the model.'
  } else if (hasAnyDeployed && !canRetrain) {
    text =
      'Your previous model is still deployed. Your team can now still use the previous model in their IDE. You cannot retain at this time, please contact support.'
  } else if (!hasAnyDeployed && canRetrain) {
    text = 'Please review the recent training run or try retraining the model.'
  } else {
    text = 'There is currently no deployed model available. For more help please contact support.'
  }

  return (
    <Banner
      description={
        <Box sx={{display: 'flex', flexDirection: 'column', gap: '0.25rem'}}>
          <BannerTitle isListItem={isListItem}>The training for {org} model failed.</BannerTitle>
          <Text sx={{wordBreak: 'break-word'}}>{text}</Text>
        </Box>
      }
      primaryAction={
        canRetrain ? <Banner.PrimaryAction onClick={handleRetrainClick}>Try again</Banner.PrimaryAction> : undefined
      }
      secondaryAction={
        canViewDetails ? (
          <Banner.SecondaryAction onClick={() => navigate(showPath)}>View training run</Banner.SecondaryAction>
        ) : undefined
      }
      style={isListItem ? isListItemStyle : undefined}
      variant="critical"
    />
  )
}
