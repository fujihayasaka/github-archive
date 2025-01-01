import {GitHubAvatar} from '@github-ui/github-avatar'
import {SafeHTMLDiv, type SafeHTMLString} from '@github-ui/safe-html'
import {AlertIcon, InfoIcon, StopIcon} from '@primer/octicons-react'
import {Button, Text, Truncate} from '@primer/react'
import {clsx} from 'clsx'

import type {DiffAnnotation} from '../types'
import {DiffAnnotationLevels} from '../types'
import styles from './Annotation.module.css'
import {AnnotationPresentationMap} from './AnnotationIcon'

const IconMap = {
  [DiffAnnotationLevels.Failure]: <StopIcon className="fgColor-danger" />,
  [DiffAnnotationLevels.Warning]: <AlertIcon className="fgColor-attention" />,
  [DiffAnnotationLevels.Notice]: <InfoIcon className="fgColor-muted" />,
}

/**
 * A check annotation
 * Preferred method is to pass in ghostUser from the app payload
 * Because this is a shared package, ghostUser is optional and will default to constants
 */
export function Annotation({annotation}: {annotation: DiffAnnotation}) {
  return (
    <div
      className={clsx(
        'p-3 bgColor-default',
        AnnotationPresentationMap[annotation.annotationLevel].borderColor,
        styles.annotation,
      )}
    >
      <div className="d-flex flex-items-center mb-2">
        {IconMap[annotation.annotationLevel]}
        <Text weight="semibold" className="fgColor-muted pl-2" size="small">
          {AnnotationPresentationMap[annotation.annotationLevel].ariaLabel}
        </Text>
      </div>
      <div className="ml-4">
        {annotation.title && (
          <Text
            weight="semibold"
            size="medium"
            className={AnnotationPresentationMap[annotation.annotationLevel].primaryColorClass}
          >
            {annotation.title}
          </Text>
        )}
      </div>
      <h2 className="sr-only">
        {AnnotationPresentationMap[annotation.annotationLevel].ariaLabel}: {annotation.title}
      </h2>
      <div className="mb-3 mt-1 ml-4">
        {/* Message is sanitized from the server, see PullRequests::PageData::Annotations::Loader */}
        {annotation.message && (
          <SafeHTMLDiv html={annotation.message as SafeHTMLString} className={styles.annotationMessage} />
        )}
      </div>
      <div className="d-flex flex-items-center flex-justify-between ml-4">
        <div className={styles.annotationSource}>
          <GitHubAvatar src={annotation.appAvatarUrl} alt={annotation.appAvatarAltText} />
          <Truncate
            className="ml-2"
            maxWidth="300px"
            inline
            title={`${annotation.checkSuiteName} / ${annotation.checkRun.name}`}
          >
            <Text weight="semibold" size="small">
              {annotation.checkSuiteName}
            </Text>{' '}
            / <Text size="small">{annotation.checkRun.name}</Text>
          </Truncate>
        </div>
        {annotation.checkRun.detailsUrl && (
          <Button as="a" href={annotation.checkRun.detailsUrl} size="small">
            View details
          </Button>
        )}
      </div>
    </div>
  )
}
