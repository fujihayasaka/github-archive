import {WithShimmerEffect} from '@github-ui/copilot-chat/components/WithShimmerEffect'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {LabelPickerLabel$data} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import {CheckIcon, CopilotErrorIcon, CopilotIcon, SyncIcon, XIcon} from '@primer/octicons-react'
import {IconButton, Label} from '@primer/react'
import {Suspense, useCallback, useEffect, useState, useTransition} from 'react'
import {LABELS} from '../../constants/labels'
import {setUserRejectedCopilotLabelsSuggestion, type CopilotRequestStatus} from '../../utils/copilot-utils'
import {Section} from '../Section'
import {SectionHeader} from '../SectionHeader'
import styles from './CopilotLabelsSection.module.css'

export type CopilotLabelsSectionProps = {
  issueBody: string
  issueId: string
  issueTitle: string
  repositoryName?: string
  repositoryOwner?: string
  sectionHeader: JSX.Element
  setShouldShowCopilotComponent: (shouldShowCopilotComponent: boolean) => void
  suggestedLabels: LabelPickerLabel$data[]
  labelsStatus: CopilotRequestStatus
  onConfirmLabels: (selectedSuggestions: LabelPickerLabel$data[]) => void
  onErrorRetry: () => void
}

export function CopilotLabelsSection({
  issueId,
  sectionHeader,
  setShouldShowCopilotComponent,
  suggestedLabels,
  labelsStatus,
  onConfirmLabels,
  onErrorRetry,
}: CopilotLabelsSectionProps) {
  // Add isPending state to inform users when a transition is happening
  const [isPending, startContentTransition] = useTransition()

  const onCancelCopilotLabels = useCallback(() => {
    startContentTransition(() => {
      setShouldShowCopilotComponent(false)
      sendEvent('copilot_suggested_labels.dismiss', {
        labels: suggestedLabels.map(label => label.name).join(','),
        issueId,
      })
      setUserRejectedCopilotLabelsSuggestion(issueId)
    })
  }, [suggestedLabels, issueId, setShouldShowCopilotComponent, startContentTransition])

  const onErrorCancel = useCallback(() => {
    startContentTransition(() => {
      setShouldShowCopilotComponent(false)
      sendEvent('copilot_suggested_labels_error.cancel')
    })
  }, [setShouldShowCopilotComponent, startContentTransition])

  // Use the Suspense boundary appropriately
  return (
    <Suspense fallback={<CopilotLabelsSectionLoading />}>
      <Section sectionHeader={sectionHeader}>
        {labelsStatus === 'loading' && (
          <span className="d-flex flex-items-center pl-2 py-1" aria-live="polite" aria-busy={isPending}>
            <CopilotIcon className={styles.copilotIcon} />
            <WithShimmerEffect>
              <span className={styles.copilotLoadingText}>Copilot is thinking &hellip;</span>
            </WithShimmerEffect>
          </span>
        )}
        {labelsStatus === 'success' && (
          <CopilotLabelsSectionSuccess
            labels={suggestedLabels}
            onConfirm={onConfirmLabels}
            onCancel={onCancelCopilotLabels}
            setShouldShowCopilotComponent={setShouldShowCopilotComponent}
            startContentTransition={startContentTransition}
            issueId={issueId}
          />
        )}
        {labelsStatus === 'error' && <CopilotLabelsSectionError onRetry={onErrorRetry} onCancel={onErrorCancel} />}
      </Section>
    </Suspense>
  )
}

function CopilotLabelsSectionLoading() {
  return (
    <Section sectionHeader={<SectionHeader title={LABELS.sectionTitles.labels} readonly />}>
      <span className="d-flex flex-items-center pl-2 py-1" aria-busy="true" aria-live="polite">
        <CopilotIcon className={styles.copilotIcon} />
        <WithShimmerEffect>
          <span className={styles.copilotLoadingText}>Copilot is thinking &hellip;</span>
        </WithShimmerEffect>
      </span>
    </Section>
  )
}

function CopilotLabelsSectionSuccess({
  labels,
  onConfirm,
  onCancel,
  setShouldShowCopilotComponent,
  startContentTransition,
  issueId,
}: {
  labels: LabelPickerLabel$data[]
  onConfirm: (sl: LabelPickerLabel$data[]) => void
  onCancel: () => void
  setShouldShowCopilotComponent: (shouldShow: boolean) => void
  startContentTransition: (callback: () => void) => void
  issueId: string
}) {
  const [selectedLabelSuggestions, setSelectedLabelSuggestions] = useState<LabelPickerLabel$data[]>(labels)
  useEffect(() => {
    if (labels.length === 0 || selectedLabelSuggestions.length === 0) {
      startContentTransition(() => {
        setShouldShowCopilotComponent(false)
      })
    }
  }, [labels, setShouldShowCopilotComponent, startContentTransition, selectedLabelSuggestions])

  // Early return with null if no labels without immediately calling setState
  if (labels.length === 0) {
    return null
  }

  sendEvent('copilot_suggested_labels.shown', {issueId})

  return (
    <span className="d-flex flex-items-start flex-justify-between pl-0">
      <div className={styles.copilotDraftLabelsContainer}>
        {selectedLabelSuggestions.map(label => (
          <CopilotDraftLabels
            key={label.id}
            name={label.name}
            onRemove={() => setSelectedLabelSuggestions(selectedLabelSuggestions.filter(l => l.id !== label.id))}
          />
        ))}
      </div>
      <span className="d-flex flex-items-center pl-1">
        <IconButton
          variant="invisible"
          size="small"
          icon={CheckIcon}
          onClick={() => onConfirm(selectedLabelSuggestions)}
          aria-label="Accept suggestions"
        />
        <IconButton variant="invisible" size="small" icon={XIcon} onClick={onCancel} aria-label="Dismiss suggestions" />
      </span>
    </span>
  )
}

function CopilotLabelsSectionError({onRetry, onCancel}: {onRetry: () => void; onCancel: () => void}) {
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

function CopilotDraftLabels({onRemove, name}: {onRemove: () => void; name: string}) {
  const labelRemoveButton = (
    // Removing tooltip here because it visually hides the labels that are rendered below it
    // we still have the aria label so screen readers should announce it
    // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
    <IconButton
      variant="invisible"
      size="small"
      icon={XIcon}
      onClick={onRemove}
      aria-label={`Dismiss ${name}`}
      style={{color: 'var(--fgColor-muted)'}}
      unsafeDisableTooltip
    />
  )
  return (
    <div className={styles.copilotDraftLabel}>
      <Label className={styles.copilotDraftIndividualLabel}>
        {name} {labelRemoveButton}
      </Label>
    </div>
  )
}
