import {CodeIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'

import type {PublicCodeReference} from '../../utils/copilot-chat-types'
import {AnnotationsList} from './AnnotationsList'

export interface ReferenceAnnotationsProps {
  references: PublicCodeReference[]
}

type Repository = {
  name: string
  url?: string
  license?: string | null
}

const BLOB_REGEX = /^(?<repoURL>https?:\/\/(?<repoName>github.com\/[^/]+\/[^/]+))\/tree\/[0-9a-f]+\//

type Blob = {
  url: string
  repoURL: string
  repoName: string
  path: string
}

function referencesToRepos(references: PublicCodeReference[]): Repository[] {
  const repos = new Map<string, Repository>()

  for (const annotation of references) {
    const match = BLOB_REGEX.exec(annotation.sourceURL)

    if (match && match.groups) {
      const {repoName, repoURL} = match.groups as Blob

      repos.set(repoName, {
        name: repoName,
        url: repoURL,
        license: annotation.license === 'NOASSERTION' ? null : annotation.license,
      })
    }
  }

  return Array.from(repos.values())
}

export function ReferenceAnnotations({references}: ReferenceAnnotationsProps) {
  const repositories = referencesToRepos(references)

  return (
    <AnnotationsList
      icon={
        <span style={{color: 'var(--fgColor-attention)'}}>
          <CodeIcon />
        </span>
      }
      summary={`Public code references from ${repositories.length} ${
        repositories.length === 1 ? 'repository' : 'repositories'
      }`}
    >
      {repositories.map(repo => (
        <ActionList.LinkItem href={repo.url} key={repo.name}>
          {repo.name}
          <ActionList.Description>{repo.license} license</ActionList.Description>
        </ActionList.LinkItem>
      ))}
    </AnnotationsList>
  )
}
