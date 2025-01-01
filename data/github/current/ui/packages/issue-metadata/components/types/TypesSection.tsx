import {Box, type SxProp} from '@primer/react'
import {useMemo, useCallback, useState} from 'react'
import {graphql, readInlineData, useFragment, useRelayEnvironment} from 'react-relay'

import {LABELS} from '../../constants/labels'
import {ReadonlySectionHeader} from '../ReadonlySectionHeader'
import {Section} from '../Section'
import {SectionHeader} from '../SectionHeader'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {ERRORS} from '@github-ui/item-picker/Errors'
import type {
  IssueTypePickerIssueType$data,
  IssueTypePickerIssueType$key,
} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import type {TypesSectionFragment$key} from './__generated__/TypesSectionFragment.graphql'
import type {TypesSectionTypeFragment$key} from './__generated__/TypesSectionTypeFragment.graphql'
import {IssueTypeFragment, IssueTypePicker} from '@github-ui/item-picker/IssueTypePicker'
import {commitUpdateIssueIssueTypeMutation} from '@github-ui/item-picker/commitUpdateIssueIssueTypeMutation'
import {IssueType} from './IssueType'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {CopilotTypesSection} from './CopilotTypesSection'

const ReadonlyTypesSectionHeader = () => <ReadonlySectionHeader title={LABELS.sectionTitles.types} />

type TypesSectionProps = {
  sectionHeader: JSX.Element
  type: IssueTypePickerIssueType$data | null
  repoNameWithOwner?: string
} & SxProp

const TypesSection = ({sectionHeader, type, repoNameWithOwner, sx}: TypesSectionProps) => (
  <Section sx={sx} sectionHeader={sectionHeader} emptyText={type ? undefined : LABELS.emptySections.types}>
    <Box sx={{ml: 2, mt: 1}}>
      <IssueType type={type} repoNameWithOwner={repoNameWithOwner} />
    </Box>
  </Section>
)

export type CreateIssueIssueTypesSectionProps = {
  repo: string
  owner: string
  type: IssueTypePickerIssueType$data | null
  onSelectionChange: (type: IssueTypePickerIssueType$data[] | null) => void
  viewerCanType: boolean
  insidePortal: boolean
  shortcutEnabled: boolean
} & SxProp
export function CreateIssueIssueTypesSection({
  type,
  onSelectionChange,
  viewerCanType,
  sx,
  ...sharedConfigProps
}: CreateIssueIssueTypesSectionProps) {
  const sectionHeader = () => {
    if (!viewerCanType) {
      return <ReadonlyTypesSectionHeader />
    } else {
      return (
        <IssueTypePicker
          onSelectionChange={newType => {
            onSelectionChange(newType)
          }}
          readonly={viewerCanType}
          activeIssueType={type}
          anchorElement={(anchorProps, ref) => (
            <SectionHeader title={LABELS.sectionTitles.types} buttonProps={anchorProps} ref={ref} />
          )}
          {...sharedConfigProps}
          width="medium"
        />
      )
    }
  }

  const {repo, owner} = sharedConfigProps

  return <TypesSection sx={sx} sectionHeader={sectionHeader()} type={type} repoNameWithOwner={`${owner}/${repo}`} />
}

const TypesSectionTypeFragment = graphql`
  fragment TypesSectionTypeFragment on Issue {
    issueType {
      ...IssueTypePickerIssueType
    }
  }
`

const TypesSectionFragment = graphql`
  fragment TypesSectionFragment on Issue {
    repository {
      name
      nameWithOwner
      owner {
        login
      }
      issueTypes(first: 10) {
        edges {
          node {
            id
          }
        }
      }
    }
    id
    ...TypesSectionTypeFragment
    viewerCanType
  }
`

type EditIssueIssueTypesSectionProps = {
  issue: TypesSectionFragment$key
  onIssueUpdate?: () => void
  singleKeyShortcutsEnabled: boolean
  insideSidePanel?: boolean
}
export function EditIssueIssueTypeSection({
  issue,
  onIssueUpdate,
  singleKeyShortcutsEnabled,
  insideSidePanel,
}: EditIssueIssueTypesSectionProps) {
  const data = useFragment(TypesSectionFragment, issue)
  const {
    repository: {
      owner: {login: owner},
      name: repo,
      nameWithOwner,
      issueTypes,
    },
    id: issueId,
    viewerCanType,
  } = data

  const formattedIssueTypes = issueTypes?.edges?.map(edge => edge?.node?.id) || []

  const {issueType} = useFragment<TypesSectionTypeFragment$key>(TypesSectionTypeFragment, data)

  const activeType =
    issueType !== undefined
      ? // eslint-disable-next-line no-restricted-syntax
        readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, issueType)
      : null

  const {addToast} = useToastContext()
  const environment = useRelayEnvironment()

  const copilot_auto_assign_metadata = isFeatureEnabled('copilot_auto_assign_metadata')

  // only show the copilot component if
  // 1. feature flag is enabled,
  // 2. the user can change the issue type, AND
  // 3. there is no type assigned to issue
  const [shouldShowCopilotComponent, setShouldShowCopilotComponent] = useState(
    copilot_auto_assign_metadata && viewerCanType && (activeType === null || activeType === undefined),
  )

  const onSelectionChanged = useCallback(
    (selectedTypes: IssueTypePickerIssueType$data[]) => {
      commitUpdateIssueIssueTypeMutation({
        environment,
        input: {issueId, issueTypeId: selectedTypes.length > 0 ? selectedTypes[0]?.id : null},
        onError: () =>
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotUpdateType,
          }),
        onCompleted: onIssueUpdate,
      })
    },
    [addToast, environment, issueId, onIssueUpdate],
  )

  const sectionHeader = useMemo(() => {
    if (!viewerCanType) {
      return <ReadonlyTypesSectionHeader />
    }

    return (
      <IssueTypePicker
        repo={repo}
        owner={owner}
        onSelectionChange={onSelectionChanged}
        anchorElement={(anchorProps, ref) => (
          <SectionHeader title={LABELS.sectionTitles.types} buttonProps={anchorProps} ref={ref} />
        )}
        readonly={!viewerCanType}
        shortcutEnabled={singleKeyShortcutsEnabled}
        activeIssueType={activeType ?? null}
        insidePortal={insideSidePanel}
        width="medium"
      />
    )
  }, [viewerCanType, repo, owner, onSelectionChanged, singleKeyShortcutsEnabled, activeType, insideSidePanel])

  if (!viewerCanType && formattedIssueTypes.length === 0) return null

  if (!shouldShowCopilotComponent) {
    return <TypesSection sectionHeader={sectionHeader} type={activeType ?? null} repoNameWithOwner={nameWithOwner} />
  } else {
    return (
      <CopilotTypesSection
        issueId={issueId}
        onIssueUpdate={onIssueUpdate}
        setShouldShowCopilotComponent={setShouldShowCopilotComponent}
        nameWithOwner={nameWithOwner}
      />
    )
  }
}
