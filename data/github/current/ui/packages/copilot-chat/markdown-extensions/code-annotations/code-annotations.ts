import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName, parseJsonAttribute} from '@github-ui/copilot-markdown/utils'
import {createElement} from 'react'
import {visit} from 'unist-util-visit'

import type {Annotation, CodeVulnerability, PublicCodeReference} from '../../utils/copilot-chat-types'
import {AnnotationsBlock, referenceAnnotationsAttribute, vulnerabilityAnnotationsAttribute} from './AnnotationsBlock'
import type {CodeAnnotations} from './types'

const vulnerabilityAnnotationsProperty = dataAttrToPropName(vulnerabilityAnnotationsAttribute)
const referenceAnnotationsProperty = dataAttrToPropName(referenceAnnotationsAttribute)

type TextAnnotation<T> = Annotation<T> & {
  text: string
}

interface AnnotationsExtensionOptions {
  publicCodeReferences: Array<Annotation<PublicCodeReference>>
  vulnerabilities: Array<Annotation<CodeVulnerability>>
}

// Make sure this is defined outside the function so it never changes; this would cause the components to get remounted
const reactComponents: ReactComponentsExtension = {
  div: (props, fallthrough) => {
    const references = parseJsonAttribute<PublicCodeReference[]>(props, referenceAnnotationsAttribute) ?? undefined
    const vulnerabilities =
      parseJsonAttribute<CodeVulnerability[]>(props, vulnerabilityAnnotationsAttribute) ?? undefined

    if (!references && !vulnerabilities) return fallthrough

    return createElement(AnnotationsBlock, {references, vulnerabilities})
  },
}

export function codeAnnotationsExtension({
  publicCodeReferences: referenceAnnotations = [],
  vulnerabilities: vulnerabilityAnnotations = [],
}: AnnotationsExtensionOptions): CopilotMarkdownExtension {
  let referenceAnnotationsWithText: Array<TextAnnotation<PublicCodeReference>> = []
  let vulnerabilityAnnotationsWithText: Array<TextAnnotation<CodeVulnerability>> = []

  return {
    preprocessMarkdown(markdown) {
      referenceAnnotationsWithText = referenceAnnotations.map(annotation => ({
        ...annotation,
        text: markdown.substring(annotation.startOffset, annotation.endOffset + 1),
      }))

      vulnerabilityAnnotationsWithText = vulnerabilityAnnotations.map(annotation => ({
        ...annotation,
        text: markdown.substring(annotation.startOffset, annotation.endOffset + 1),
      }))

      return markdown
    },

    transformMarkdown: tree =>
      visit(tree, 'code', (node, i, parent) => {
        if (i === undefined || !parent) return

        const references = referenceAnnotationsWithText
          .filter(({text}) => node.value.includes(text))
          .map(a => a.details)
        const vulnerabilities = vulnerabilityAnnotationsWithText
          .filter(({text}) => node.value.includes(text))
          .map(a => a.details)
        if (references.length + vulnerabilities.length === 0) return

        const annotationsNode: CodeAnnotations = {
          type: 'codeAnnotations',
          references,
          vulnerabilities,
          children: [],
          data: {
            hName: 'div',
            hProperties: {
              [referenceAnnotationsProperty]: JSON.stringify(references),
              [vulnerabilityAnnotationsProperty]: JSON.stringify(vulnerabilities),
            },
            hChildren: [],
          },
        }
        parent.children.splice(i + 1, 0, annotationsNode)
      }),

    reactComponents,
  }
}
