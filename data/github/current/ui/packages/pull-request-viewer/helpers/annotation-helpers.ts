import type {DiffAnnotation} from '@github-ui/conversations'

export type DiffAnnotationsByPathMap = {
  [path: string]: DiffAnnotationsByEndLineMap
}

export type DiffAnnotationsByEndLineMap = {
  [endLineNumber: number]: DiffAnnotation[]
}

/**
 * Transforms array of annotations into a map of annotations by path and endline
 */
export function groupAnnotationsByPath(diffAnnotations: DiffAnnotation[]): DiffAnnotationsByPathMap {
  const mappedAnnotations: DiffAnnotationsByPathMap = {}

  diffAnnotations.map(annotation => {
    const annotationPath = annotation.path
    const annotationEndLine = annotation.endLine

    if (!!annotationPath && !!annotationEndLine) {
      // Ensure path key exists
      mappedAnnotations[annotationPath] = mappedAnnotations[annotationPath] ?? {}
      // Ensure endLine key exists
      mappedAnnotations[annotationPath][annotationEndLine] = mappedAnnotations[annotationPath][annotationEndLine] ?? []

      // Add annotation to map of annotations by path and endline
      mappedAnnotations[annotationPath][annotationEndLine] = [
        ...mappedAnnotations[annotationPath][annotationEndLine],
        annotation,
      ]
    }
  })
  return mappedAnnotations
}
