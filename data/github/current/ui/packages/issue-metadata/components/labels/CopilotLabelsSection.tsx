import {useRelayEnvironment} from 'react-relay'
import type {LabelPickerLabel$data} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import {Suspense, useCallback, useEffect} from 'react'
import {useCopilot} from '../../utils/useCopilot'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {ERRORS} from '@github-ui/item-picker/Errors'
import {SectionHeader} from '../SectionHeader'
import {Section} from '../Section'
import {commitSetLabelsForLabelableMutation} from '@github-ui/item-picker/commitSetLabelsForLabelableMutation'
import CopilotBadge from '@github-ui/copilot-chat/components/CopilotBadge'
import {CheckIcon, SyncIcon, XIcon} from '@primer/octicons-react'
import {Button, Text} from '@primer/react'
import {LabelsList} from '@github-ui/labels-list'
import {TEST_IDS} from '../../constants/test-ids'
import {LABELS} from '../../constants/labels'

export type CopilotLabelsSectionProps = {
  onIssueUpdate?: () => void
  issueId: string
  setShouldShowCopilotComponent: (shouldShowCopilotComponent: boolean) => void
}

export function CopilotLabelsSection({
  issueId,
  onIssueUpdate,
  setShouldShowCopilotComponent,
}: CopilotLabelsSectionProps) {
  const {fetchSuggestions, copilotLabels, copilotRequestSuccess} = useCopilot()

  const {addToast} = useToastContext()
  const environment = useRelayEnvironment()

  const onSelectionChanged = useCallback(
    (selectedLabels: LabelPickerLabel$data[]) => {
      commitSetLabelsForLabelableMutation({
        environment,
        input: {labelableId: issueId, labels: selectedLabels, labelableTypeName: 'Issue'},
        onError: () =>
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotUpdateLabels,
          }),
        onCompleted: onIssueUpdate,
      })
    },
    [addToast, environment, issueId, onIssueUpdate],
  )

  // This useEffect hook is responsible for making a request to the fetch the labels suggestions for the given issue.
  // Behind the scenes, in useCopilot hook, the fetch Suggestions first calls the graphql query to get the issue title,
  // body, and all the labels in the repository that the issue belongs. It then makes a call to Copilot API using the
  // fetched data (title, body, and labels) to to suggest the appropriate labels for the issue.
  useEffect(() => {
    fetchSuggestions({issueId, environment, type: 'labels'})
  }, [environment, fetchSuggestions, issueId])

  const onConfirmCopilotLabels = useCallback(() => {
    onSelectionChanged(copilotLabels)
    setShouldShowCopilotComponent(false)
  }, [onSelectionChanged, copilotLabels, setShouldShowCopilotComponent])

  return (
    <Suspense fallback={<CopilotLabelsSectionLoading />}>
      <Section sectionHeader={<SectionHeader title={LABELS.sectionTitles.labels} readonly />}>
        {copilotRequestSuccess === 'loading' ? (
          <span className="d-flex flex-items-center pl-1">
            <CopilotBadge isLoading />
            <Text sx={{paddingLeft: 2, fontSize: 1}}>Copilot is thinking...</Text>
          </span>
        ) : copilotRequestSuccess === 'success' ? (
          <span className="d-flex flex-items-center flex-justify-between pl-0 pb-1">
            <LabelsList sx={{pt: 0, pb: 0}} labels={copilotLabels} testId={TEST_IDS.issueLabels} />
            <span className="d-flex flex-items-center pl-1">
              <Button
                variant="invisible"
                size="small"
                icon={CheckIcon}
                onClick={onConfirmCopilotLabels}
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
                  fetchSuggestions({issueId, environment, type: 'labels'})
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

function CopilotLabelsSectionLoading() {
  return (
    <Section sectionHeader={<SectionHeader title={LABELS.sectionTitles.labels} readonly />}>
      <span className="d-flex flex-items-center pl-1">
        <CopilotBadge isLoading />
        <Text sx={{paddingLeft: 2, fontSize: 1}}>Copilot is thinking...</Text>
      </span>
    </Section>
  )
}
