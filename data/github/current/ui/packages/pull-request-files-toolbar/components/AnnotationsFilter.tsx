import type {DiffAnnotation} from '@github-ui/conversations'
import {SearchIcon} from '@primer/octicons-react'
import {TextInput} from '@primer/react'
import type {AnnotationsPayload} from '../page-data/payloads/annotations'

/**
 * Return a set of annotation ids that match the current filter state
 */
export function getFilteredAnnotations(annotations: AnnotationsPayload, filteredText: string): Set<string> {
  const matchingAnnotationIds = annotations
    .filter(annotation => filterAnnotation(annotation, filteredText))
    .map(annotation => annotation.id)
  return new Set(matchingAnnotationIds)
}

function filterAnnotation(annotation: DiffAnnotation, filteredText: string) {
  if (filteredText) {
    const filteredTextLowerCase = filteredText.toLowerCase()
    if (
      !annotation.annotationLevel.toLowerCase().includes(filteredTextLowerCase) &&
      !annotation.message.toLowerCase().includes(filteredTextLowerCase) &&
      !annotation.path.toLowerCase().includes(filteredTextLowerCase) &&
      !annotation.title?.toLowerCase().includes(filteredTextLowerCase) &&
      !annotation.checkRun.name?.toLowerCase().includes(filteredTextLowerCase) &&
      !annotation.appAvatarAltText.toLowerCase().includes(filteredTextLowerCase) &&
      !annotation.checkSuiteName?.toLowerCase().includes(filteredTextLowerCase)
    ) {
      return false
    }
  }

  return true
}

type AnnotationsFilterProps = {
  className?: string
  filteredText: string
  onFilteredTextChange: (filterText: string) => void
}

export function AnnotationsFilter({className, filteredText, onFilteredTextChange}: AnnotationsFilterProps) {
  return (
    <div className={className}>
      <TextInput
        block
        aria-label="Filter annotations…"
        leadingVisual={SearchIcon}
        placeholder="Filter annotations…"
        value={filteredText}
        onChange={event => onFilteredTextChange(event.target.value)}
      />
    </div>
  )
}
