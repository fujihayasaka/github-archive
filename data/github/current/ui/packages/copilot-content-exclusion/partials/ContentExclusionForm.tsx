import {PreviewCardOutlet} from '@github-ui/preview-card'
import {ContentExclusionSettings} from '../components/ContentExclusionSettings'
import type {ContentExclusionSettingsPayload} from '../types'
import {ContentExclusionPaths} from '../components/ContentExclusionPaths'

export default function ContentExclusionFormApp(props: {
  initialPayload: ContentExclusionSettingsPayload
  contentExclusionSaveSpeedbump: boolean
}) {
  const {document, lastEdited, endpoint = ''} = props.initialPayload

  const locationCopy = 'Choose the repositories and paths that GitHub Copilot should exclude.'
  const applyCopy = 'All exclusions defined will apply to all members of your enterprise.'

  return (
    <>
      <ContentExclusionSettings locationCopy={locationCopy} applyCopy={applyCopy}>
        <ContentExclusionPaths
          endpoint={endpoint}
          initialLastEdited={lastEdited}
          initialValue={document ?? ''}
          label="Repositories and paths to exclude:"
          placeholder={placeholder}
          contentExclusionSaveSpeedbumpFlag={props.contentExclusionSaveSpeedbump}
        />
      </ContentExclusionSettings>

      <PreviewCardOutlet />
    </>
  )
}

const placeholder = `# Example patterns:

git@ssh.dev.azure.com:v3/org/project/repo:
 - **/*.env

git@internal.corp.net:my-team/my-repo:
 - /**/*.env
 - /*/releases/**/*
`
