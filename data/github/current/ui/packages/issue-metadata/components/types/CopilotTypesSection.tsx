import {useRelayEnvironment} from 'react-relay'
import type {IssueTypePickerIssueType$data} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'

import {Suspense, useCallback, useEffect} from 'react'
import {useCopilot} from '../../utils/useCopilot'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {ERRORS} from '@github-ui/item-picker/Errors'
import {SectionHeader} from '../SectionHeader'
import {Section} from '../Section'
import CopilotBadge from '@github-ui/copilot-chat/components/CopilotBadge'
import {CheckIcon, SyncIcon, XIcon} from '@primer/octicons-react'
import {Button, Text} from '@primer/react'
import {LABELS} from '../../constants/labels'
import {commitUpdateIssueIssueTypeMutation} from '@github-ui/item-picker/commitUpdateIssueIssueTypeMutation'
import {IssueTypeToken} from '@github-ui/issue-type-token'

export type CopilotTypesSectionProps = {
  onIssueUpdate?: () => void
  issueId: string
  setShouldShowCopilotComponent: (shouldShowCopilotComponent: boolean) => void
  nameWithOwner: string
}

export function CopilotTypesSection({
  issueId,
  onIssueUpdate,
  setShouldShowCopilotComponent,
  nameWithOwner,
}: CopilotTypesSectionProps) {
  const {copilotType, copilotRequestSuccess, fetchSuggestions} = useCopilot()

  const {addToast} = useToastContext()
  const environment = useRelayEnvironment()

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

  // This useEffect hook is responsible for making a request to the fetch the suggested type for the given issue.
  // Behind the scenes, in useCopilot hook, the fetch Suggestions first calls the graphql query to get the issue title,
  // body, and all the types in the repository that the issue belongs. It then makes a call to Copilot API using the
  // fetched data (title, body, and issue types) to suggest the appropriate type for the issue.
  useEffect(() => {
    fetchSuggestions({issueId, environment, type: 'issueType'})
  }, [environment, fetchSuggestions, issueId])

  const onConfirmCopilotType = useCallback(() => {
    if (copilotType !== undefined) onSelectionChanged([copilotType])
    setShouldShowCopilotComponent(false)
  }, [copilotType, onSelectionChanged, setShouldShowCopilotComponent])

  return (
    <Suspense fallback={<CopilotTypesSectionLoading />}>
      <Section sectionHeader={<SectionHeader title={LABELS.sectionTitles.types} readonly />}>
        {copilotRequestSuccess === 'loading' ? (
          <span className="d-flex flex-items-center pl-1">
            <CopilotBadge isLoading />
            <Text sx={{paddingLeft: 2, fontSize: 1}}>Copilot is thinking...</Text>
          </span>
        ) : copilotRequestSuccess === 'success' ? (
          <span className="d-flex flex-items-center flex-justify-between pl-2 pt-1">
            <IssueTypeToken
              name={copilotType?.name || ''}
              color={copilotType?.color || ''}
              href={`/${nameWithOwner}/issues?q=type:"${copilotType?.name}"`}
              getTooltipText={(isTruncated: boolean) => (isTruncated ? copilotType?.name : undefined)}
              sx={{mr: 2}}
            />
            <span className="d-flex flex-items-center pl-1">
              <Button
                variant="invisible"
                size="small"
                icon={CheckIcon}
                onClick={onConfirmCopilotType}
                aria-label="Confirm"
              />
              <Button
                variant="invisible"
                size="small"
                icon={XIcon}
                onClick={() => setShouldShowCopilotComponent(false)}
                aria-label="Cancel"
              />
            </span>
          </span>
        ) : (
          <span className="d-flex flex-items-center flex-justify-between pl-1">
            <span className="d-flex flex-items-center pl-1">
              <CopilotBadge isError />
              <Text sx={{paddingLeft: 2, fontSize: 1}}>{`Error. Please try again.`}</Text>
            </span>
            <span className="d-flex flex-items-center pl-1">
              <Button
                variant="invisible"
                size="small"
                icon={SyncIcon}
                onClick={() => {
                  fetchSuggestions({issueId, environment, type: 'issueType'})
                }}
                aria-label="Retry"
              />
              <Button
                variant="invisible"
                size="small"
                icon={XIcon}
                onClick={() => setShouldShowCopilotComponent(false)}
                aria-label="Cancel"
              />
            </span>
          </span>
        )}
      </Section>
    </Suspense>
  )
}

function CopilotTypesSectionLoading() {
  return (
    <Section sectionHeader={<SectionHeader title={LABELS.sectionTitles.types} readonly />}>
      <span className="d-flex flex-items-center pl-1">
        <CopilotBadge isLoading />
        <Text sx={{paddingLeft: 2, fontSize: 1}}>Copilot is thinking...</Text>
      </span>
    </Section>
  )
}
