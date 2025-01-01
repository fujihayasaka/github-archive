import {GitHubAvatar} from '@github-ui/github-avatar'
import {AlertIcon, InfoIcon, StopIcon} from '@primer/octicons-react'
import {Box, Button, Text, Truncate} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import type {DiffAnnotation} from '../types'
import {DiffAnnotationLevels} from '../types'
import {AnnotationPresentationMap} from './AnnotationIcon'

const IconMap = {
  [DiffAnnotationLevels.Failure]: <Octicon icon={StopIcon} sx={{fill: 'danger.fg'}} />,
  [DiffAnnotationLevels.Warning]: <Octicon icon={AlertIcon} sx={{fill: 'attention.fg'}} />,
  [DiffAnnotationLevels.Notice]: <Octicon icon={InfoIcon} sx={{fill: 'fg.muted'}} />,
}

/**
 * A check annotation
 * Preferred method is to pass in ghostUser from the app payload
 * Because this is a shared package, ghostUser is optional and will default to constants
 */
export function Annotation({annotation}: {annotation: DiffAnnotation}) {
  const lineClampStyles = {
    display: '-webkit-box',
    overflow: 'hidden',
    '-webkit-box-orient': 'vertical',
    '-webkit-line-clamp': '8',
    maxWidth: 'unset',
  }

  return (
    <Box
      sx={{
        borderLeft: '6px solid',
        borderColor: AnnotationPresentationMap[annotation.annotationLevel].primaryColor,
        p: 4,
      }}
    >
      <Box sx={{display: 'flex', alignItems: 'center', mb: 2}}>
        {IconMap[annotation.annotationLevel]}
        <Text sx={{fontWeight: 600, color: 'fg.muted', fontSize: 0, pl: 2}}>
          {AnnotationPresentationMap[annotation.annotationLevel].ariaLabel}
        </Text>
      </Box>
      <Text
        sx={{color: AnnotationPresentationMap[annotation.annotationLevel].primaryColor, fontWeight: 600, fontSize: 1}}
      >
        {annotation.title}
      </Text>
      <Box sx={{mb: 3, mt: 1}}>
        {annotation.message && (
          <Text sx={{fontFamily: 'var(--fontStack-monospace)', fontSize: 0, ...lineClampStyles}}>
            {annotation.message}
          </Text>
        )}
      </Box>
      <Box sx={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
        <Box sx={{flexGrow: 2}}>
          <GitHubAvatar src={annotation.appAvatarUrl} alt={annotation.appAvatarAltText} />
          <Truncate
            sx={{ml: 2, maxWidth: '300px'}}
            inline
            title={`${annotation.checkSuiteName} / ${annotation.checkRun.name}`}
          >
            <Text sx={{fontWeight: 600, fontSize: 0}}>{annotation.checkSuiteName}</Text> /{' '}
            <Text sx={{fontSize: 0}}>{annotation.checkRun.name}</Text>
          </Truncate>
        </Box>
        {annotation.checkRun.detailsUrl && (
          <Button as="a" href={annotation.checkRun.detailsUrl} size="small">
            View details
          </Button>
        )}
      </Box>
    </Box>
  )
}
