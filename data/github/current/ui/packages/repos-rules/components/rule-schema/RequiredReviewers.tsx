import {
  Box,
  Button,
  Checkbox,
  FormControl,
  IconButton,
  SelectPanel,
  Text,
  Textarea,
  Truncate,
  VisuallyHidden,
} from '@primer/react'
import type {
  ParameterValue,
  RegisteredRuleSchemaComponent,
  RequiredReviewerError,
  RulesetRoutePayload,
  SchemaField,
  ValidationError,
} from '../../types/rules-types'
import {forwardRef, useCallback, useEffect, useMemo, useRef, useState, type FC, type RefObject} from 'react'
import {Blankslate, DataTable, Dialog, Table} from '@primer/react/experimental'
import {AlertFillIcon, InfoIcon, PencilIcon, PeopleIcon, PlusIcon, TriangleDownIcon} from '@primer/octicons-react'
import {useRelativeNavigation} from '../../hooks/use-relative-navigation'
import {IntegerField} from './builtin/IntegerField'
import {debounce} from '@github/mini-throttle'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {AlphaLabel} from '@github-ui/lifecycle-labels/alpha'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {RulesetFormErrorFlash} from '../RulesetFormErrorFlash'

// Data shape for saving the require reviewer data
export type RequiredReviewer = {
  reviewer_id: string
  minimum_approvals: number
  file_patterns: string[]
}

// Metadata returned from the pull request rule
export type PullRequestRuleMetadata = {
  requiredReviewers: Record<string, RequiredReviewerMetadata>
}

// Metadata for each required reviewer
// We may have null values for the metadata if the required reviewer is not found
type RequiredReviewerMetadata = {
  id: number | null
  globalRelayId: string
  type: string | null
  name: string | null
  // Used to determine if the required reviewer is new or not. A new reviewer is added to the top of the list.
  // We only set this value in the UI
  isNew?: boolean
}

export function RequiredReviewers({
  field,
  readOnly,
  value,
  onValueChange,
  metadata,
  errors,
  fieldRef,
}: RegisteredRuleSchemaComponent) {
  const requiredReviewerList = useMemo(() => (value || []) as RequiredReviewer[], [value])
  const {baseAvatarUrl} = useRoutePayload<RulesetRoutePayload>()
  const {resolvePath} = useRelativeNavigation()
  const suggestionsUrl = resolvePath('required_reviewer_suggestions')

  const [requiredReviewerMetadata, setRequiredReviewerMetadata] = useState<Record<string, RequiredReviewerMetadata>>(
    () => (metadata as PullRequestRuleMetadata)?.requiredReviewers || {},
  )

  // Return the reviewers in the preferred order to be displayed in the table
  const requiredReviewers = useMemo(() => {
    const newReviewers = [] as RequiredReviewer[]
    let orderedByName = [] as RequiredReviewer[]
    const missingReviewers = [] as RequiredReviewer[]

    for (const reviewer of requiredReviewerList) {
      const m = requiredReviewerMetadata[reviewer.reviewer_id]
      if (m && m.isNew) {
        newReviewers.push(reviewer)
      } else if (m && m.id && m.name) {
        const index = orderedByName.findIndex(r => {
          const compareMetadata = requiredReviewerMetadata[r.reviewer_id]
          return (m.name || '').localeCompare(compareMetadata?.name || '') <= 0
        })
        if (index === -1) {
          orderedByName.push(reviewer)
        } else {
          orderedByName = [...orderedByName.slice(0, index), reviewer, ...orderedByName.slice(index)]
        }
      } else {
        missingReviewers.push(reviewer)
      }
    }
    // For ordering, we want the reviewers that were just added while editing this rule to be at the top
    // After, we will surface the reviewers that are missing
    // Finally we will sort the exisiting reviewers by name
    return [...newReviewers, ...missingReviewers, ...orderedByName]
  }, [requiredReviewerMetadata, requiredReviewerList])

  const [ruleChecked, setRuleChecked] = useState<boolean>(requiredReviewers.length > 0)

  const [showDialog, setShowDialog] = useState(false)

  // Used to pass the required reviewer to the dialog for editing
  const [editRequiredReviewer, setEditRequiredReviewer] = useState<RequiredReviewer | undefined>(undefined)

  const onEditRequiredReviewer = (requiredReviewer: RequiredReviewer) => {
    setEditRequiredReviewer(requiredReviewer)
    setShowDialog(true)
  }

  const deleteRequiredReviewer = useCallback(
    (requiredReviewer: RequiredReviewer) => {
      const index = requiredReviewers.findIndex(r => r.reviewer_id === requiredReviewer.reviewer_id)
      const updatedRequiredReviewers: RequiredReviewer[] = [
        ...requiredReviewers.slice(0, index),
        ...requiredReviewers.slice(index + 1),
      ]
      onValueChange(updatedRequiredReviewers)
    },
    [onValueChange, requiredReviewers],
  )

  const addOrUpdateRequiredReviewer = useCallback(
    (requiredReviewer: RequiredReviewer, newMetadata?: RequiredReviewerMetadata) => {
      let updatedRequiredReviewers: RequiredReviewer[]
      if (editRequiredReviewer) {
        // Update required reviewer data used for saving
        const index = requiredReviewers.findIndex(r => r.reviewer_id === editRequiredReviewer.reviewer_id)
        updatedRequiredReviewers = [
          ...requiredReviewers.slice(0, index),
          requiredReviewer,
          ...requiredReviewers.slice(index + 1),
        ]
      } else {
        // If we are creating a new required reviewer, add it to the top of the list for visibility
        updatedRequiredReviewers = [requiredReviewer, ...requiredReviewers]
      }
      if (newMetadata) {
        // Update metadata
        setRequiredReviewerMetadata(previousMetadata => ({
          ...previousMetadata,
          [requiredReviewer.reviewer_id]: newMetadata,
        }))
      }
      onValueChange(updatedRequiredReviewers)
    },
    [editRequiredReviewer, onValueChange, requiredReviewers],
  )

  const onCheckboxChange = (isChecked: boolean) => {
    setRuleChecked(isChecked)
    if (!isChecked) {
      // If the rule is being unchecked, then we need to clear the required reviewers
      // This is to ensure the rule is not saved when it is unchecked
      onValueChange([])
    }
  }

  const firstErrorRef = useRef<string | undefined>(undefined)

  const {errorsByReviewer, genericErrors} = useMemo(() => {
    const ruleErrors = {} as Record<string, string[]>
    const reviewerErrors = {} as Record<string, ValidationError>
    for (const error of (errors[0]?.sub_errors || []) as RequiredReviewerError[]) {
      if (error.reviewer_id !== undefined && error.error_code !== 'reviewer_not_found') {
        // Focus on the first row with an error
        firstErrorRef.current = firstErrorRef.current || error.reviewer_id
        // If there is an error on a specific reviewer, set the error for that reviewer id
        // We can use this to display the error on the appropriate row
        reviewerErrors[error.reviewer_id] = error
      } else {
        // Reset the ref if we have a generic error
        // Instead of focusing on a specific row, we are going to focus on the generic error banner above the table
        firstErrorRef.current = undefined
        ruleErrors[error.error_code] = ruleErrors[error.error_code] || []
        if (!ruleErrors[error.error_code]) {
          ruleErrors[error.error_code] = []
        }
        ruleErrors[error.error_code] = ruleErrors[error.error_code] || []
        ruleErrors[error.error_code]!.push(error.message)
      }
    }
    return {
      errorsByReviewer: reviewerErrors,
      genericErrors: ruleErrors,
    }
  }, [errors])

  const fieldLabel = `${field.name}Label`

  // Start of datatable pagination configuration
  const pageSize = 10
  const [isPaginated, setIsPaginated] = useState(pageSize < requiredReviewers.length)
  const [currentPaginatedPage, setCurrentPaginatedPage] = useState(0)
  const paginationStart = currentPaginatedPage * pageSize
  const paginationEnd = paginationStart + pageSize
  const rows = requiredReviewers.slice(paginationStart, paginationEnd)

  // This useEffect is used to update the pagination state when the required reviewers change
  useEffect(() => {
    // if we are paginated and we were on a page that no longer exists, go back a page
    if (isPaginated && currentPaginatedPage > 0 && currentPaginatedPage * pageSize >= requiredReviewers.length) {
      setCurrentPaginatedPage(currentPaginatedPage - 1)
    }
    setIsPaginated(pageSize < requiredReviewers.length)

    // Exclude isPaginated because we don't want to rerender the table when the pagination state changes
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requiredReviewers.length, pageSize, currentPaginatedPage])

  // End of datatable pagination configuration

  // // This useEffect is used for retoggling the checkbox on revert
  useEffect(() => {
    // If he rule is not checked and we have required reviewers, then we need to check the rule
    // This will recheck the rule on revert
    if (!ruleChecked && requiredReviewerList.length > 0) {
      setRuleChecked(true)
    }
    // Exclude ruleChecked because we don't want to rerender the checkbox when the rule is checked
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requiredReviewerList])

  return (
    <>
      {!readOnly ? (
        <>
          <FormControl>
            <Checkbox
              aria-labelledby={fieldLabel}
              checked={ruleChecked}
              onChange={e => {
                onCheckboxChange(e.target.checked)
              }}
            />
            <FormControl.Label id={fieldLabel}>
              {field.display_name}
              <AlphaLabel className="ml-2" />
            </FormControl.Label>
            <FormControl.Caption>{field.description}</FormControl.Caption>
          </FormControl>
          {genericErrors && Object.keys(genericErrors).length > 0 && (
            <RulesetFormErrorFlash sx={{ml: 4}} errorId={fieldLabel} errorRef={fieldRef as RefObject<HTMLDivElement>}>
              <Box as="ul" sx={{listStyleType: 'none'}}>
                {Object.entries(genericErrors).map(([key, values]) => (
                  <li key={key}>{[...new Set(values)].join(', ')}</li>
                ))}
              </Box>
            </RulesetFormErrorFlash>
          )}
        </>
      ) : (
        ruleChecked && (
          <div>
            <span className="d-flex flex-items-center text-bold">
              {field.display_name}
              <AlphaLabel className="ml-2" />
            </span>
            <span className="d-block text-small color-fg-muted">{field.description}</span>
          </div>
        )
      )}

      {ruleChecked && (
        <>
          <Table.Container
            sx={
              !readOnly
                ? {
                    // Forcing the top of the datatable to not have a border
                    // in order to add an additional header row with the add button
                    '.TableHead .TableRow:first-of-type .TableHeader': {
                      borderTop: 'none',
                    },
                    '.TableHead .TableRow:first-of-type .TableHeader:first-child, .TableHead .TableRow:first-of-type .TableHeader:last-child':
                      {
                        borderTopLeftRadius: 0,
                        borderTopRightRadius: 0,
                      },
                    pt: 3,
                    ml: 4,
                  }
                : {
                    pt: 3,
                  }
            }
          >
            {!readOnly ? (
              <Box
                className="Box-header m-0 p-2 d-flex flex-justify-between flex-items-center"
                sx={{gridColumn: '1/-1'}}
              >
                <div className="Box-title px-2">{`${requiredReviewers.length} reviewers`}</div>
                <Button leadingVisual={PlusIcon} aria-haspopup="dialog" onClick={() => setShowDialog(true)}>
                  Add reviewer
                </Button>
              </Box>
            ) : null}
            {requiredReviewers.length === 0 ? (
              <Box
                className="Box"
                sx={{gridColumn: '1/-1', borderTop: 'none', borderTopLeftRadius: 0, borderTopRightRadius: 0}}
              >
                <Blankslate>
                  <Blankslate.Heading>No reviewers have been added</Blankslate.Heading>
                </Blankslate>
              </Box>
            ) : (
              <DataTable
                data={rows.map(reviewer => ({
                  ...reviewer,
                  actor: requiredReviewerMetadata[reviewer.reviewer_id],
                  id: reviewer.reviewer_id,
                }))}
                cellPadding="condensed"
                columns={[
                  {
                    header: 'Reviewer',
                    field: 'actor',
                    rowHeader: true,
                    maxWidth: '25%',
                    renderCell: row => {
                      return (
                        <div>
                          {row.actor?.id ? (
                            <>
                              <Box
                                sx={{
                                  alignItems: 'center',
                                  display: 'flex',
                                  gap: 2,
                                }}
                              >
                                <ActorAvatar actor={row.actor} baseAvatarUrl={baseAvatarUrl} />
                                <span>{row.actor?.name}</span>
                              </Box>
                              {errorsByReviewer[row.reviewer_id] && (
                                <Text
                                  sx={{display: 'flex', alignItems: 'center', gap: 2, fontSize: 0, color: 'danger.fg'}}
                                  id={`${row.reviewer_id}-error`}
                                >
                                  <AlertFillIcon size={12} />
                                  <span>{errorsByReviewer[row.reviewer_id]?.message}</span>
                                </Text>
                              )}
                            </>
                          ) : (
                            <Text
                              sx={{display: 'flex', alignItems: 'center', gap: 2, fontSize: 0, color: 'danger.fg'}}
                              id={`${row.reviewer_id}-error`}
                            >
                              <AlertFillIcon size={12} />
                              <span>Reviewer not found</span>
                            </Text>
                          )}
                        </div>
                      )
                    },
                  },
                  {
                    header: 'Approvals',
                    field: 'minimum_approvals',
                    width: 'auto',
                    renderCell: row => <span>{row.minimum_approvals}</span>,
                  },
                  {
                    header: 'File patterns',
                    field: 'file_patterns',
                    width: 'grow',
                    maxWidth: '50%',
                    renderCell: row => <FilePatternGroup filePatterns={row.file_patterns} />,
                  },
                  {
                    header: () => <VisuallyHidden>Actions</VisuallyHidden>,
                    id: 'actions',
                    width: 70,
                    renderCell: row => (
                      <IconButton
                        type="button"
                        icon={readOnly ? InfoIcon : PencilIcon}
                        aria-label={`${readOnly ? 'View' : 'Edit'} ${
                          row.actor?.id ? row.actor.name : 'the required reviewer'
                        }'s file patterns`}
                        size="small"
                        variant="invisible"
                        ref={
                          row.reviewer_id === firstErrorRef.current
                            ? (fieldRef as RefObject<HTMLButtonElement>)
                            : undefined
                        }
                        sx={{
                          display: 'flex',
                          alignItems: 'center',
                        }}
                        onClick={() => onEditRequiredReviewer(row)}
                      />
                    ),
                  },
                ]}
              />
            )}
            {isPaginated && (
              <Table.Pagination
                aria-label="Pagination for required reviewers"
                pageSize={pageSize}
                totalCount={requiredReviewers.length}
                onChange={pageInfo => {
                  setCurrentPaginatedPage(pageInfo.pageIndex)
                }}
              />
            )}
          </Table.Container>
        </>
      )}
      {showDialog && (
        <ReviewerDialog
          field={field}
          currentRequiredReviewers={requiredReviewers}
          baseAvatarUrl={baseAvatarUrl}
          existingRequiredReviewer={
            editRequiredReviewer
              ? {
                  requiredReviewer: editRequiredReviewer,
                  metadata: requiredReviewerMetadata[editRequiredReviewer.reviewer_id],
                }
              : undefined
          }
          onDelete={deleteRequiredReviewer}
          onSave={addOrUpdateRequiredReviewer}
          onClose={() => {
            setShowDialog(false)
            setEditRequiredReviewer(undefined)
          }}
          suggestionsUrl={suggestionsUrl}
          readOnly={readOnly}
        />
      )}
    </>
  )
}

const FilePatternGroup = ({filePatterns}: {filePatterns: string[]}) => {
  const [showFilePatternOverlay, setShowFilePatternOverlay] = useState<boolean>(false)
  const hiddenFilePatterns = filePatterns.slice(1)
  if (filePatterns.length === 0) {
    return null
  }
  return (
    <>
      <div className="d-flex flex-items-center width-fit">
        <Box
          sx={{
            backgroundColor: 'neutral.subtle',
            borderRadius: 2,
            marginY: 1,
            maxWidth: '100%',
            paddingX: 1,
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            '&:not(:last-child)': {
              marginRight: 1,
            },
            fontFamily: 'mono',
          }}
        >
          <Truncate title={filePatterns[0] as string} maxWidth={200}>
            {filePatterns[0]}
          </Truncate>
        </Box>
        {hiddenFilePatterns.length > 0 && (
          <Button
            variant="invisible"
            size="small"
            onClick={() => {
              setShowFilePatternOverlay(true)
            }}
          >
            <VisuallyHidden>Show +{hiddenFilePatterns.length} more</VisuallyHidden>
            <span aria-hidden="true" className="fg-color-muted">
              + {hiddenFilePatterns.length} more
            </span>
          </Button>
        )}
      </div>
      {showFilePatternOverlay && (
        <Dialog
          title="File patterns"
          onClose={() => {
            setShowFilePatternOverlay(false)
          }}
        >
          <div className="d-flex flex-column">
            <pre className="bgColor-inset f5 mt-1 overflow-x-auto p-3 rounded-2 text-mono">
              {filePatterns.join('\n')}
            </pre>
            <Text sx={{fontSize: 0, mt: 1, fontWeight: 'normal', color: 'fg.muted'}}>
              Pull requests which change matching files must be approved by the specified team.
            </Text>
          </div>
        </Dialog>
      )}
    </>
  )
}

/**
 * ↑↑↑                                                                                   ↑↑↑
 * ↑↑↑ The code above is part of the rule row form as additional options for the PR rule ↑↑↑
 * ↑↑↑                                                                                   ↑↑↑
 *
 * ↓↓↓                                                                    ↓↓↓
 * ↓↓↓ The code below here is all related to the required reviewer dialog ↓↓↓
 * ↓↓↓                                                                    ↓↓↓
 */

type ReviewerDialogProps = {
  field: SchemaField
  currentRequiredReviewers: RequiredReviewer[]
  existingRequiredReviewer?: {requiredReviewer: RequiredReviewer; metadata?: RequiredReviewerMetadata}
  onSave: (requiredReviewer: RequiredReviewer, newMetadata?: RequiredReviewerMetadata) => void
  onDelete: (requiredReviewer: RequiredReviewer) => void
  onClose: () => void
  suggestionsUrl: string
  baseAvatarUrl: string
  readOnly?: boolean
}

const ReviewerDialog: FC<ReviewerDialogProps> = ({
  field,
  currentRequiredReviewers,
  existingRequiredReviewer,
  onDelete,
  onClose,
  onSave,
  suggestionsUrl,
  baseAvatarUrl,
  readOnly,
}) => {
  const {requiredReviewer: existingReviewer, metadata} = existingRequiredReviewer || {}

  // For reviewer select panel
  const [selectedReviewer, setSelectedReviewer] = useState<SuggestionItem | undefined>(() => {
    // Check metadata because it will be `null` if the reviewer is not found
    return existingReviewer && metadata && metadata.id && metadata.name && metadata.type
      ? {
          id: existingReviewer?.reviewer_id,
          dbId: metadata.id,
          type: metadata.type,
          text: metadata.name,
          description: calculateDescription(metadata.name, metadata.type),
          leadingVisual: () => (
            <ActorAvatar
              actor={{id: metadata.id, type: metadata.type, name: metadata.name}}
              baseAvatarUrl={baseAvatarUrl}
            />
          ),
        }
      : undefined
  })
  const [reviewerError, setReviewerError] = useState<string | undefined>(undefined)

  // Approvals dropdown
  const [minimumApprovals, setMinimumApprovals] = useState<number>(existingReviewer?.minimum_approvals || 0)

  // File pattern textbox
  const [filePatterns, setFilePatterns] = useState<string>(existingReviewer?.file_patterns.join('\n') || '')
  const [filePatternsError, setFilePatternsError] = useState<string | undefined>(undefined)
  // Placeholder text for file pattern text box
  const placeholderText = `*
scripts/foo.js
scripts/*
*.js
`
  const filePatternDescription =
    (field.type === 'array' &&
      field.content_object &&
      field.content_object.fields.find(f => f.name === 'file_patterns')?.description) ||
    'File patterns'

  const [reviewerMetadata, setReviewerMetadata] = useState<RequiredReviewerMetadata | undefined>(metadata)

  // This is used to focus on the first error field when the dialog is opened
  const firstErrorField = useRef<HTMLTextAreaElement | HTMLButtonElement | null>(null)
  const selectPanelRef = useRef<HTMLButtonElement | null>(null)
  const textAreaRef = useRef<HTMLTextAreaElement | null>(null)

  const onDeleteClick = useCallback(() => {
    if (existingReviewer) {
      onDelete(existingReviewer)
    }
    onClose()
  }, [existingReviewer, onClose, onDelete])

  const validateReviewer = useCallback(
    (reviewerIdValue: string | undefined, setErrorField: boolean = false) => {
      // Clear validation errors
      setReviewerError(undefined)
      if (!reviewerIdValue) {
        setReviewerError('A reviewer must be selected')
        if (setErrorField) {
          firstErrorField.current = selectPanelRef.current
        }
      }
      // We don't allow adding (or changing an existing reviwer to) a team that is already added as a reviewer
      if (
        existingReviewer?.reviewer_id !== reviewerIdValue &&
        currentRequiredReviewers.find(r => r.reviewer_id === reviewerIdValue)
      ) {
        setReviewerError('This team is already added as a reviewer')
        if (setErrorField) {
          firstErrorField.current = selectPanelRef.current
        }
      }
    },
    [currentRequiredReviewers, existingReviewer?.reviewer_id],
  )

  const validateValues = useCallback(
    (reviewerIdValue: string | undefined, filePatternValue: string[]) => {
      // Clear validation error
      setFilePatternsError(undefined)
      firstErrorField.current = null
      validateReviewer(reviewerIdValue, true)
      if (filePatternValue.length === 0) {
        setFilePatternsError('At least one file pattern must be specified')
        if (!firstErrorField.current) {
          firstErrorField.current = textAreaRef.current
        }
      }
      firstErrorField.current?.focus()
      firstErrorField.current?.scrollIntoView({behavior: 'smooth', block: 'center', inline: 'center'})
      // If we have a first error field, return false, which indicates values are not valid
      return !firstErrorField.current
    },
    [validateReviewer],
  )

  const onDone = useCallback(() => {
    const formattedFilePatterns = filePatterns.split('\n').filter(line => line.trim() !== '')
    if (validateValues(selectedReviewer?.id, formattedFilePatterns)) {
      onSave(
        {
          reviewer_id: selectedReviewer?.id,
          minimum_approvals: minimumApprovals,
          file_patterns: formattedFilePatterns,
        } as RequiredReviewer,
        reviewerMetadata,
      )
      onClose()
    }
  }, [filePatterns, minimumApprovals, onClose, onSave, reviewerMetadata, selectedReviewer?.id, validateValues])

  const updateMinimumApprovals = (value: ParameterValue) => {
    setMinimumApprovals(value as number)
  }

  const updateFilePatterns = (value: ParameterValue) => {
    setFilePatternsError(undefined)
    setFilePatterns(value as string)
  }

  const onSelect = (actor: ItemInput | undefined, options: SuggestionItem[]) => {
    let selected: SuggestionItem | undefined = undefined
    if (actor === undefined) {
      // deselect the reviewer
      setSelectedReviewer(undefined)
      setReviewerMetadata(undefined)
    } else {
      selected = options.find(item => item.id === actor?.id)
      if (selected) {
        setSelectedReviewer(selected)
        setReviewerMetadata({
          id: selected.dbId,
          name: selected.text,
          type: selected.type,
          globalRelayId: selected.id,
          isNew: !existingReviewer,
        } as RequiredReviewerMetadata)
      }
    }
    validateReviewer(selected?.id)
  }

  return (
    <Dialog
      aria-label={`${readOnly ? 'Reviewer details' : `${existingRequiredReviewer ? 'Edit' : 'Add'} reviewer`}`}
      title={`${readOnly ? 'Reviewer details' : `${existingRequiredReviewer ? 'Edit' : 'Add'} reviewer`}`}
      renderFooter={() => {
        if (!readOnly) {
          return (
            <Dialog.Footer>
              <div className="d-flex flex-justify-between flex-1">
                {existingRequiredReviewer && (
                  <div>
                    <Button variant="danger" onClick={onDeleteClick}>
                      Delete
                    </Button>
                  </div>
                )}
                <div className="d-flex flex-justify-end flex-1 gap-2">
                  <Button variant="default" onClick={onClose}>
                    Cancel
                  </Button>
                  <Button variant="primary" onClick={onDone}>
                    Done
                  </Button>
                </div>
              </div>
            </Dialog.Footer>
          )
        }
      }}
      onClose={onClose}
      width="large"
    >
      {!readOnly ? (
        <FormControl sx={{mb: 3}}>
          <FormControl.Label required>Reviewer</FormControl.Label>
          <RequiredReviewersSelectPanel
            ref={selectPanelRef}
            suggestionsUrl={suggestionsUrl}
            baseAvatarUrl={baseAvatarUrl}
            selectedReviewer={selectedReviewer}
            onSelect={onSelect}
          />
          {reviewerError && (
            <FormControl.Validation variant="error" aria-live="polite">
              {reviewerError}
            </FormControl.Validation>
          )}
        </FormControl>
      ) : (
        <div className="d-flex flex-column mb-3">
          <span className="d-flex flex-items-center text-bold">Reviewer</span>
          <Box
            sx={{
              alignItems: 'center',
              display: 'flex',
              gap: 2,
              marginTop: 1,
            }}
          >
            {metadata && (
              <ActorAvatar
                actor={{id: metadata?.id, type: metadata?.type, name: metadata?.name}}
                baseAvatarUrl={baseAvatarUrl}
              />
            )}
            <span>{metadata?.name || 'Reviewer was not found'}</span>
          </Box>
        </div>
      )}
      {!readOnly ? (
        <div className="mb-3">
          <IntegerField
            field={{
              type: 'integer',
              name: 'minimumApprovals',
              description: '',
              display_name: 'Approvals',
              required: false,
              allowed_range: '0..10',
              default_value: 0,
              beta: false,
            }}
            value={minimumApprovals}
            onValueChange={updateMinimumApprovals}
            errors={[]}
            sourceType="enterprise"
          />
        </div>
      ) : (
        <div className="d-flex flex-column mb-3">
          <span className="d-flex flex-items-center text-bold">Approvals</span>
          <span className="mt-1">{minimumApprovals}</span>
        </div>
      )}

      {!readOnly ? (
        <FormControl>
          <FormControl.Label required>File patterns</FormControl.Label>
          <FormControl.Caption>{filePatternDescription}</FormControl.Caption>
          <Textarea
            block
            ref={textAreaRef}
            value={filePatterns}
            onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) => updateFilePatterns(e.target.value)}
            sx={{fontFamily: 'mono', whiteSpace: 'pre'}}
            placeholder={placeholderText}
            wrap="off"
          />
          {filePatternsError && (
            <FormControl.Validation variant="error" aria-live="polite">
              {filePatternsError}
            </FormControl.Validation>
          )}
        </FormControl>
      ) : (
        <div className="d-flex flex-column">
          <span className="d-flex flex-items-center text-bold">File patterns</span>
          <pre className="bgColor-inset f5 mt-1 overflow-x-auto p-3 rounded-2 text-mono">{filePatterns}</pre>
          <Text sx={{fontSize: 0, mt: 1, fontWeight: 'normal', color: 'fg.muted'}}>
            Pull requests which change matching files must be approved by the specified team.
          </Text>
        </div>
      )}
    </Dialog>
  )
}

// The expected returned type from the suggestions endpoint
type SuggestionActor = {
  id: number
  name: string
  type: string
  global_relay_id: string
}

const getSuggestions = async (url: string, query: string): Promise<SuggestionActor[]> => {
  const requestUrl = `${url}?q=${encodeURIComponent(query)}`
  const response = await verifiedFetchJSON(requestUrl, {
    method: 'GET',
  })
  if (response.ok) {
    try {
      return await response.json()
    } catch {
      throw new Error('Failed to read response')
    }
  } else {
    throw new Error('Unexpected error')
  }
}

// The shape of the suggestion item used in the select panel
type SuggestionItem = {
  id: string // Uses global relay id since it will be unique across all actors
  dbId: number | null
  text: string
  description: string
  type: string
  disabled?: boolean
  renderItem?: () => JSX.Element
  leadingVisual: () => JSX.Element
}

const calculateDescription = (name: string, type: string) => {
  const description = type === 'EnterpriseTeam' ? 'Enterprise team' : type
  return `${description} • @${name}`
}

const ActorAvatar = ({
  actor,
  baseAvatarUrl,
}: {
  actor?: Pick<RequiredReviewerMetadata, 'id' | 'type' | 'name'>
  baseAvatarUrl: string
}) => {
  if (actor === undefined) {
    return null
  }
  if (actor.type === 'Team' && actor.name) {
    return (
      <GitHubAvatar
        className="flex-shrink-0"
        alt={`${actor.name} Avatar`}
        src={`${baseAvatarUrl}/t/${actor.id}`}
        size={16}
      />
    )
  }
  if (actor.type === 'EnterpriseTeam') {
    return <PeopleIcon className="color-fg-muted flex-shrink-0" />
  }
  return null
}

type RequiredReviewersSelectPanelProps = {
  suggestionsUrl: string
  baseAvatarUrl: string
  selectedReviewer: SuggestionItem | undefined
  onSelect: (actor: ItemInput | undefined, options: SuggestionItem[]) => void
}

const RequiredReviewersSelectPanel = forwardRef<HTMLButtonElement | null, RequiredReviewersSelectPanelProps>(
  ({suggestionsUrl, baseAvatarUrl, selectedReviewer, onSelect}, ref) => {
    const [suggestions, setSuggestions] = useState<SuggestionActor[]>([])
    const suggestionItems: SuggestionItem[] = useMemo(() => {
      const mappedSuggestions = suggestions.map(s => ({
        id: s.global_relay_id,
        dbId: s.id,
        type: s.type,
        text: s.name,
        description: calculateDescription(s.name, s.type),
        leadingVisual: () => (
          <ActorAvatar actor={{id: s.id, type: s.type, name: s.name}} baseAvatarUrl={baseAvatarUrl} />
        ),
      }))
      return mappedSuggestions
    }, [suggestions, baseAvatarUrl])

    const [isLoading, setIsLoading] = useState(false)
    const [open, setOpen] = useState(false)
    const [filter, setFilter] = useState('')
    const [selected, setSelected] = useState(selectedReviewer)

    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    const debounceSuggestions = useCallback(
      debounce(async (newFilter: string) => {
        setIsLoading(true)
        if (newFilter === '') {
          setSuggestions(await getSuggestions(suggestionsUrl, ''))
        } else {
          setSuggestions(await getSuggestions(suggestionsUrl, newFilter))
        }
        setIsLoading(false)
      }, 200),
      [suggestionsUrl, setSuggestions],
    )

    const onSelectChange = (actor: ItemInput | undefined) => {
      onSelect(actor, suggestionItems)
    }

    const onOpen = async () => {
      if (!open) {
        setOpen(true)
        setIsLoading(true)
        setSuggestions(await getSuggestions(suggestionsUrl, ''))
        setIsLoading(false)
      } else {
        setOpen(false)
      }
    }

    useEffect(() => {
      if (!selectedReviewer) {
        setSelected(undefined)
        return
      }
      if (suggestionItems.length > 0) {
        setSelected(suggestionItems.find(item => item.id === selectedReviewer?.id))
      }
    }, [selectedReviewer, suggestionItems])

    return (
      <SelectPanel
        loading={isLoading}
        placeholderText={'Search reviewers'}
        anchorRef={ref as RefObject<HTMLButtonElement>}
        renderAnchor={({children, 'aria-labelledby': ariaLabelledBy, ...anchorProps}) => (
          <Button
            trailingVisual={TriangleDownIcon}
            aria-labelledby={` ${ariaLabelledBy}`}
            {...anchorProps}
            aria-haspopup="dialog"
          >
            {children ?? 'Select reviewer'}
          </Button>
        )}
        open={open}
        onOpenChange={onOpen}
        items={
          suggestionItems.length > 0
            ? suggestionItems
            : // We use the below to handle an empty state. But we can replace this
              // with the new EmptyState functionality once it is available.
              // https://github.com/primer/react/pull/5142
              [
                {
                  id: 'no-matches',
                  dbId: null,
                  type: 'no-matches',
                  text: 'No teams found',
                  disabled: true,
                  renderItem: () => (
                    <Box
                      sx={{
                        display: 'flex',
                        flexDirection: 'column',
                        justifyContent: 'center',
                        alignItems: 'center',
                        flexGrow: 1,
                        height: '100%',
                        gap: 1,
                        padding: 4,
                        textAlign: 'center',
                      }}
                    >
                      <Text sx={{fontSize: 1, fontWeight: 'bold'}}>
                        No teams found{filter.length > 0 ? ` for '${filter}'` : ''}
                      </Text>
                      <Text
                        sx={{
                          fontSize: 1,
                          color: 'fg.muted',
                          display: 'flex',
                          flexDirection: 'column',
                          gap: 2,
                          alignItems: 'center',
                        }}
                      >
                        {filter.length > 0 ? 'Adjust your search term to find other teams. ' : ''}
                        Only visible teams can be added as reviewers.
                      </Text>
                    </Box>
                  ),
                } as SuggestionItem,
              ]
        }
        selected={selected}
        onSelectedChange={onSelectChange}
        filterValue={filter}
        onFilterChange={f => {
          setFilter(f)
          debounceSuggestions(f)
        }}
        overlayProps={{
          width: 'medium',
          height: suggestionItems.length > 6 ? 'medium' : 'auto',
        }}
        title="Select reviewer"
      />
    )
  },
)

RequiredReviewersSelectPanel.displayName = 'RequiredReviewersSelectPanel'
