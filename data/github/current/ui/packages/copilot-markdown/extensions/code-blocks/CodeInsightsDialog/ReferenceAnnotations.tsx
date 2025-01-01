import {LawIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {GitHubAvatar} from '@github-ui/github-avatar'

import type {PublicCodeReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {AnnotationsList} from './AnnotationsList'

export interface ReferenceAnnotationsProps {
  references: PublicCodeReference[]
}

type Repository = {
  name: string
  owner: string
  url: string
  license?: string | null
}

/**
 * Extracts owner/repo (nwo) and repository name from a GitHub URL
 * @param url GitHub URL
 * @returns Object containing nwo and repo name, or null if URL doesn't match expected format
 */
function extractRepoInfo(url: string): {owner: string; name: string} | null {
  // Match URLs like: "https://github.com/owner/repo/tree/..."
  const match = /^https?:\/\/github\.com\/([^/]+)\/([^/]+)/.exec(url)

  if (!match || !match[1] || !match[2]) return null

  const owner = match[1]
  const name = match[2]

  return {
    owner,
    name,
  }
}

function referencesToRepos(references: PublicCodeReference[]): Repository[] {
  const repos = new Map<string, Repository>()

  for (const annotation of references) {
    const repo = extractRepoInfo(annotation.sourceURL)

    if (!repo) continue

    const {owner, name} = repo

    repos.set(name, {
      name,
      owner,
      url: `https://github.com/${owner}/${name}`,
      license: annotation.license === 'NOASSERTION' ? null : annotation.license,
    })
  }

  return Array.from(repos.values()).sort((a, b) => a.name.localeCompare(b.name))
}

export function ReferenceAnnotations({references}: ReferenceAnnotationsProps) {
  const repositories = referencesToRepos(references)

  return (
    <AnnotationsList
      icon={
        <span style={{color: 'var(--fgColor-muted)'}}>
          <LawIcon />
        </span>
      }
      summary={`Public code references from ${repositories.length} ${
        repositories.length === 1 ? 'repository' : 'repositories'
      }`}
    >
      {repositories.map(repo => (
        <ActionList.LinkItem href={repo.url} key={repo.name} tabIndex={undefined}>
          <ActionList.LeadingVisual>
            <GitHubAvatar src={`https://github.com/${repo.owner}.png`} alt={`@${repo.owner} avatar`} size={20} />
          </ActionList.LeadingVisual>
          {repo.owner}/{repo.name}
          <ActionList.Description>{repo.license ? `${repo.license} license` : 'No license'}</ActionList.Description>
        </ActionList.LinkItem>
      ))}
    </AnnotationsList>
  )
}
