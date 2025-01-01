import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ContentExclusionSettings} from '../components/ContentExclusionSettings'
import type {ContentExclusionSettingsPayload} from '../types'
import {ContentExclusionPaths} from '../components/ContentExclusionPaths'

export function RepoSettings() {
  const {entLevelRules, orgLevelRules, organization, repo, lastEdited, document} =
    useRoutePayload<ContentExclusionSettingsPayload>()

  const locationCopy = 'Choose the paths within your repository that GitHub Copilot should exclude.'
  const applyCopy = 'All exclusions defined at the repository level will apply to all the members of your enterprise.'

  return (
    <ContentExclusionSettings
      entLevelRules={entLevelRules}
      orgLevelRules={orgLevelRules}
      locationCopy={locationCopy}
      applyCopy={applyCopy}
    >
      <ContentExclusionPaths
        endpoint={`/${organization}/${repo}/settings/copilot/content_exclusion`}
        initialLastEdited={lastEdited}
        initialValue={document ?? ''}
        label="Paths to exclude in this repository:"
        placeholder={placeholder}
      />
    </ContentExclusionSettings>
  )
}

const placeholder = `# Example patterns:

- /**/*.env
- /*/releases/**/*
`
