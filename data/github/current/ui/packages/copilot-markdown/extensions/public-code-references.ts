import type {MarkedExtension, Tokens} from 'marked'

import type {Annotation, PublicCodeReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {CopilotMarkdownExtension} from '../extension'

const isCodeToken = (token: Tokens.Generic): token is Tokens.Code => token.type === 'code'

type Source = {
  label: string
  url: string
  license?: string | null
  language?: string
}

type Repository = {
  name: string
  url?: string
  license?: string | null
  sources: Map<string, Source>
}

const BLOB_REGEX = /(?<url>(?<repoURL>https?:\/\/(?<repoName>github.com\/[^/]+\/[^/]+))\/tree\/[0-9a-f]+\/(?<path>.+))/

type Blob = {
  url: string
  repoURL: string
  repoName: string
  path: string
}

function groupAnnotations(annotations: Array<Annotation<PublicCodeReference>>): Repository[] {
  const repos = new Map<string, Repository>()

  for (const a of annotations) {
    const match = BLOB_REGEX.exec(a.details.sourceURL)

    if (match && match.groups) {
      const {url, repoName, repoURL, path} = match.groups as Blob

      let repo = repos.get(repoName)

      if (!repo) {
        repo = {
          name: repoName,
          url: repoURL,
          license: a.details.license === 'NOASSERTION' ? null : a.details.license,
          sources: new Map<string, Source>(),
        }

        repos.set(repoName, repo)
      }

      if (!repo.sources.has(url)) {
        repo.sources.set(url, {
          label: path,
          url,
          license: a.details.license === 'NOASSERTION' ? null : a.details.license,
          language: a.details.language,
        })
      }
    } else {
      let repo = repos.get('other')

      if (!repo) {
        repo = {
          name: 'Other',
          sources: new Map<string, Source>(),
        }

        repos.set('other', repo)
      }

      if (!repo.sources.has(a.details.sourceURL)) {
        repo.sources.set(a.details.sourceURL, {
          label: a.details.sourceURL,
          url: a.details.sourceURL,
          license: a.details.license === 'NOASSERTION' ? null : a.details.license,
          language: a.details.language,
        })
      }
    }
  }

  return Array.from(repos.values())
}

function renderRepo(repo: Repository): HTMLAnchorElement {
  const container = document.createElement('a')
  container.classList.add('public-code-references-repo')
  container.setAttribute('href', repo.url ?? '#')
  container.textContent = repo.name

  if (repo.license !== undefined) {
    const span = document.createElement('span')
    span.classList.add('public-code-references-license')
    span.textContent = `license ${repo.license ?? 'unknown'}`
    container.appendChild(span)
  }

  return container
}

interface PublicCodeReferencesExtensionOptions {
  references: Array<Annotation<PublicCodeReference>>
}

export default function publicCodeReferencesExtension({
  references,
}: PublicCodeReferencesExtensionOptions): CopilotMarkdownExtension {
  let refsContent: string[] = []

  let refDisclaimerHandling = false
  const markedPublicCodeReferences: MarkedExtension = {
    hooks: {
      preprocess(markdown) {
        refsContent = references.map(v => {
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
          if (!isCodeToken(token) || refDisclaimerHandling) {
            return false
          }

          refDisclaimerHandling = true
          const tokenHasAnnotation = refsContent.some(string => token.raw.includes(string))
          const html = this.parser.parse([token])
          refDisclaimerHandling = false

          if (tokenHasAnnotation) {
            const container = document.createElement('div')
            container.classList.add('public-code-references')

            const codeContent = document.createElement('div')
            codeContent.classList.add('public-code-references-details')
            codeContent.innerHTML = html

            const referencesDetails = document.createElement('details')
            referencesDetails.classList.add('public-code-references-list')
            const referencesSummary = document.createElement('summary')
            const chevron = document.createElement('div')
            chevron.classList.add('public-code-references-chevron')
            const icon = document.createElement('div')
            icon.classList.add('public-code-references-icon')

            const refsByRepo = groupAnnotations(references)
            const pluralize = (n: number) => (n === 1 ? `${n} repository` : `${n} repositories`)

            referencesSummary.textContent = `Public code references from ${pluralize(refsByRepo.length)}`
            referencesSummary.prepend(icon)
            referencesSummary.appendChild(chevron)
            referencesSummary.classList.add('public-code-references-summary')

            referencesDetails.appendChild(referencesSummary)

            for (const div of groupAnnotations(references).map(renderRepo)) {
              referencesDetails.appendChild(div)
            }

            container.append(codeContent, referencesDetails)
            return container.outerHTML
          } else {
            return html
          }
        },
      },
    ],
  }

  return {
    marked: [markedPublicCodeReferences],
    sanitizer: {
      allowedClassNames: [/^public-code-references-?/],
    },
  }
}
