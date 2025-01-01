import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ContentExclusionSettings} from '../components/ContentExclusionSettings'
import type {ContentExclusionSettingsPayload} from '../types'
import {ContentExclusionPaths} from '../components/ContentExclusionPaths'

export function OrgSettings() {
  const {entLevelRules, organization, lastEdited, document} = useRoutePayload<ContentExclusionSettingsPayload>()

  const locationCopy = 'Choose the repositories and paths that GitHub Copilot should exclude.'
  const applyCopy = 'All exclusions defined will apply to all members of your organization.'

  return (
    <ContentExclusionSettings entLevelRules={entLevelRules} locationCopy={locationCopy} applyCopy={applyCopy}>
      <ContentExclusionPaths
        endpoint={`/organizations/${organization}/settings/copilot/content_exclusion`}
        initialLastEdited={lastEdited}
        initialValue={document ?? ''}
        label="Repositories and paths to exclude:"
        placeholder={placeholder}
      />
    </ContentExclusionSettings>
  )
}

const placeholder = `# Example patterns:

smile:
 - /secrets/*

git@internal.corp.net:my-team/my-repo:
 - /**/*.env
 - /*/releases/**/*
`
