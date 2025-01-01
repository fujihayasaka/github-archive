import {WithShimmerEffect} from '@github-ui/copilot-chat/components/WithShimmerEffect'
import {commitUpdateIssueIssueTypeMutation} from '@github-ui/item-picker/commitUpdateIssueIssueTypeMutation'
import {ERRORS} from '@github-ui/item-picker/Errors'
import type {IssueTypePickerIssueType$data} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {CheckIcon, CopilotErrorIcon, CopilotIcon, SyncIcon, XIcon} from '@primer/octicons-react'
import {IconButton, Label} from '@primer/react'
import {startTransition, Suspense, useCallback, useEffect} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {LABELS} from '../../constants/labels'
import {useCopilot} from '../../utils/useCopilot'
import {Section} from '../Section'
import {SectionHeader} from '../SectionHeader'
import {sendEvent} from '@github-ui/hydro-analytics'
import styles from './CopilotTypesSection.module.css'
import {setUserRejectedCopilotTypeSuggestion} from '../../utils/copilot-utils'

export type CopilotTypesSectionProps = {
  issueId: string
  onIssueUpdate?: () => void
  sectionHeader: JSX.Element
  setShouldShowCopilotComponent: (shouldShowCopilotComponent: boolean) => void
}

export function CopilotTypesSection({
  issueId,
  onIssueUpdate,
  sectionHeader,
  setShouldShowCopilotComponent,
}: CopilotTypesSectionProps) {
  const {suggestedType, getSuggestions, getStatusForType} = useCopilot()
  const {addToast} = useToastContext()
  const environment = useRelayEnvironment()

  useEffect(() => {
    if (getStatusForType('issueType') === 'success' && suggestedType === undefined) {
      setShouldShowCopilotComponent(false)
    }
  }, [getStatusForType, setShouldShowCopilotComponent, suggestedType])

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
    startTransition(() => {
      getSuggestions({issueId, environment, type: 'issueType'})
    })
  }, [environment, getSuggestions, issueId])

  const onConfirmCopilotType = useCallback(() => {
    if (suggestedType) {
      onSelectionChanged([suggestedType])
    }
    setShouldShowCopilotComponent(false)
    sendEvent('copilot_suggested_type.confirm', {type: suggestedType?.name, issueId})
  }, [issueId, onSelectionChanged, setShouldShowCopilotComponent, suggestedType])

  const onCancelCopilotType = useCallback(() => {
    setShouldShowCopilotComponent(false)
    sendEvent('copilot_suggested_type.dismiss', {type: suggestedType?.name, issueId})
    setUserRejectedCopilotTypeSuggestion(issueId)
  }, [issueId, setShouldShowCopilotComponent, suggestedType?.name])

  const onErrorRetry = useCallback(() => {
    getSuggestions({issueId, environment, type: 'issueType'})
    sendEvent('copilot_suggested_type_error.retry')
  }, [environment, getSuggestions, issueId])

  const onErrorCancel = useCallback(() => {
    setShouldShowCopilotComponent(false)
    sendEvent('copilot_suggested_type_error.cancel')
  }, [setShouldShowCopilotComponent])

  return (
    <Suspense fallback={<CopilotTypesSectionLoading />}>
      <Section sectionHeader={sectionHeader}>
        {getStatusForType('issueType') === 'loading' && (
          <span className="d-flex flex-items-center pl-2 py-1" aria-busy="true" aria-live="polite">
            <CopilotIcon className={styles.copilotIcon} />
            <WithShimmerEffect>
              <span className={styles.copilotLoadingText}>Copilot is thinking &hellip;</span>
            </WithShimmerEffect>
          </span>
        )}
        {getStatusForType('issueType') === 'success' && suggestedType !== undefined && suggestedType !== null && (
          <CopilotTypesSectionSuccess
            copilotType={suggestedType}
            onConfirmCopilotType={onConfirmCopilotType}
            onCancel={onCancelCopilotType}
            issueId={issueId}
          />
        )}
        {getStatusForType('issueType') === 'error' && (
          <CopilotTypesSectionError onRetry={onErrorRetry} onCancel={onErrorCancel} />
        )}
      </Section>
    </Suspense>
  )
}

function CopilotTypesSectionLoading() {
  return (
    <Section sectionHeader={<SectionHeader title={LABELS.sectionTitles.types} readonly />}>
      <span className="d-flex flex-items-center pl-2 py-1" aria-busy="true" aria-live="polite">
        <CopilotIcon className={styles.copilotIcon} />
        <WithShimmerEffect>
          <span className={styles.copilotLoadingText}>Copilot is thinking &hellip;</span>
        </WithShimmerEffect>
      </span>
    </Section>
  )
}

function CopilotTypesSectionSuccess({
  copilotType,
  onConfirmCopilotType,
  onCancel,
  issueId,
}: {
  copilotType: IssueTypePickerIssueType$data
  onConfirmCopilotType: () => void
  onCancel: () => void
  issueId: string
}) {
  sendEvent('copilot_suggested_type.shown', {issueId})
  return (
    <span className="d-flex flex-items-center flex-justify-between pl-2">
      <CopilotDraftType name={copilotType.name} />
      <span className="d-flex flex-items-center pl-1">
        <IconButton
          variant="invisible"
          size="small"
          icon={CheckIcon}
          onClick={onConfirmCopilotType}
          aria-label="Accept suggestion"
        />
        <IconButton variant="invisible" size="small" icon={XIcon} onClick={onCancel} aria-label="Dismiss suggestion" />
      </span>
    </span>
  )
}

function CopilotDraftType({name}: {name: string}) {
  return (
    <div className={styles.copilotDraftType}>
      <Label className={styles.copilotDraftIndividualType}>{name}</Label>
    </div>
  )
}

function CopilotTypesSectionError({onRetry, onCancel}: {onRetry: () => void; onCancel: () => void}) {
  return (
    <span className="d-flex flex-items-center flex-justify-between pl-1">
      <span className="d-flex flex-items-center pl-1 py-1">
        <CopilotErrorIcon className={styles.copilotIcon} />
        <span className={styles.copilotLoadingText}>Error. Please try again.</span>
      </span>
      <span className="d-flex flex-items-center pl-1">
        <IconButton variant="invisible" size="small" icon={SyncIcon} onClick={onRetry} aria-label="Retry" />
        <IconButton variant="invisible" size="small" icon={XIcon} onClick={onCancel} aria-label="Dismiss" />
      </span>
    </span>
  )
}
