import type {MarkedExtension, Tokens} from 'marked'

import type {Annotation, CodeVulnerability} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {CopilotMarkdownExtension} from '../extension'

const isCodeToken = (token: Tokens.Generic): token is Tokens.Code => token.type === 'code'

const pluralizeVulnerability = (count: number): string =>
  count === 1 ? `${count} vulnerability` : `${count} vulnerabilities`

interface VulnerabilitiesExtensionOptions {
  vulnerabilities: Array<Annotation<CodeVulnerability>>
}

export default function vulnerabilitiesExtension({
  vulnerabilities,
}: VulnerabilitiesExtensionOptions): CopilotMarkdownExtension {
  let vulnsContent: string[] = []

  let vulnerabilityDisclaimerRendering = false
  const markedVulnerabilities: MarkedExtension = {
    hooks: {
      preprocess(markdown) {
        vulnsContent = vulnerabilities.map(v => {
          const {startOffset, endOffset} = v
          const content = markdown.substring(startOffset, endOffset + 1)
          return content
        })

        return markdown
      },
      postprocess(html) {
        return html
      },
    },
    extensions: [
      {
        name: 'code',
        renderer(token) {
          if (!isCodeToken(token) || vulnerabilityDisclaimerRendering) {
            return false
          }

          vulnerabilityDisclaimerRendering = true
          const tokenHasAnnotation = vulnsContent.some(string => token.raw.includes(string))
          const html = this.parser.parse([token])
          vulnerabilityDisclaimerRendering = false

          if (tokenHasAnnotation) {
            const container = document.createElement('div')
            const codeContent = document.createElement('div')
            codeContent.classList.add('snippet-vulnerability-code')
            codeContent.innerHTML = html

            const vulnerabilitiesDetails = document.createElement('details')
            vulnerabilitiesDetails.classList.add('snippet-vulnerabilities-details')
            const vulnerabilitiesSummary = document.createElement('summary')
            const chevron = document.createElement('div')
            chevron.classList.add('snippet-vulnerability-chevron')
            const shield = document.createElement('div')
            shield.classList.add('snippet-vulnerability-shield-icon')

            vulnerabilitiesSummary.textContent = `${pluralizeVulnerability(vulnerabilities.length)} detected`
            vulnerabilitiesSummary.prepend(shield)
            vulnerabilitiesSummary.appendChild(chevron)
            vulnerabilitiesSummary.classList.add('snippet-vulnerability-summary')

            vulnerabilitiesDetails.appendChild(vulnerabilitiesSummary)

            for (const v of vulnerabilities) {
              const vulnerability = document.createElement('div')
              vulnerability.classList.add('snippet-vulnerability-details')
              const vulnerabilityTitle = document.createElement('p')
              vulnerabilityTitle.classList.add('snippet-vulnerability-details-title')
              const vulnerabilityDescription = document.createElement('p')
              vulnerabilityDescription.classList.add('snippet-vulnerability-details-description')
              vulnerabilityTitle.textContent = v.details.uiType
              vulnerabilityDescription.textContent = v.details.uiDescription
              vulnerability.append(vulnerabilityTitle, vulnerabilityDescription)
              vulnerabilitiesDetails.appendChild(vulnerability)
            }

            container.append(codeContent, vulnerabilitiesDetails)

            return container.outerHTML
          } else {
            return html
          }
        },
      },
    ],
  }

  return {
    marked: [markedVulnerabilities],
    sanitizer: {
      allowedClassNames: [/^snippet-vulnerabilit(y|ies)-/],
    },
  }
}
