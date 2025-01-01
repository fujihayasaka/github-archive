import type {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useClickAnalytics} from '@github-ui/use-analytics'
import type {WebCommitDialogState} from '@github-ui/web-commit-dialog'
import {Spinner, Stack} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {useLocation} from 'react-router-dom'
import type {RepoModel} from '../../../types'
import {ReviewPromptHeader} from '../../review/components/ReviewPromptHeader'
import {useModels} from '../contexts/ModelsContext'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import {promptModelIdentifierFor} from '../models'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {getSystemMessage, getUserMessage, type PromptConfig} from '../prompts'
import type {CompareMode, EvalsRow, PromptAppPayload} from '../types'
import {AddCompareRowsControls} from './AddCompareRowsControls'
import {AddEvaluatorButton} from './AddEvaluatorButton'
import {AddPromptMenu} from './AddPromptMenu'
import {ClearSessionButton} from './ClearSessionButton'
import {CommitButton} from './CommitButton'
import {CompareRunButton} from './CompareRunButton'
import {DatasetTable} from './DatasetTable'
import {EvaluatorOutlet} from './EvaluatorOutlet'
import {ImportRows} from './ImportRows'
import {PromptEditorDialog} from './PromptEditorDialog'
import {PromptFileHeader} from './PromptFileHeader'
import {PromptLayout} from './PromptLayout'
import {PromptsTable} from './PromptsTable'
import PromptWebCommitDialog from './PromptWebCommitDialog'
import {RowEditDialog} from './RowEditDialog'
import {ViewSwitcher} from './ViewSwitcher'
import {filterAndCleanRowVariables, referencedVariablesInPrompt, VariableExpected} from '../variables'

type CompareProps = {
  modelClient: AzureModelClient
  mode: CompareMode
  isNewPrompt?: boolean
}

export function Compare({modelClient, mode = 'compare', isNewPrompt = false}: CompareProps) {
  const manager = usePromptCompareManager()
  const {
    payload: {canEdit},
  } = useAppPayload<PromptAppPayload>()
  const {error, prompts, compare, isDirty} = usePromptCompareState()
  const [dialogState, setDialogState] = useState<WebCommitDialogState>('closed')
  const {isRunning, rows, skippedRowIds, evaluators, result} = compare
  const enabledRows = useMemo(() => rows.filter(row => !skippedRowIds.has(row.id)), [rows, skippedRowIds])
  const [runButtonEnabled, setRunButtonEnabled] = useState(false)
  const [runButtonTooltip, setRunButtonTooltip] = useState('')

  const hasValidUserPrompt = useMemo(() => {
    let hasUserPrompt = false
    for (const prompt of prompts) {
      if (!prompt.messages) return false

      hasUserPrompt = prompt.messages.some(m => m.role === 'user' && !!m.message.trim())
    }
    return hasUserPrompt
  }, [prompts])

  useEffect(() => {
    if (rows?.length === 0) {
      setRunButtonEnabled(false)
      setRunButtonTooltip('Add rows to run')
      return
    } else if (enabledRows?.length === 0) {
      setRunButtonEnabled(false)
      setRunButtonTooltip('Unskip a row to run')
      return
    } else if (prompts.length === 0) {
      setRunButtonEnabled(false)
      setRunButtonTooltip('Add prompts to run')
      return
    } else if (prompts.some(p => !p.model)) {
      setRunButtonEnabled(false)
      setRunButtonTooltip('Select a model for each prompt to run')
      return
    } else if (!hasValidUserPrompt) {
      setRunButtonEnabled(false)
      setRunButtonTooltip('Every prompt needs a user prompt to run')
      return
    }

    setRunButtonEnabled(true)
    setRunButtonTooltip('')
  }, [prompts, hasValidUserPrompt, enabledRows?.length, rows?.length])

  const models = useModels()

  const [showAddRowDialog, setShowAddRowDialog] = useState(false)
  const [showEditRowDialog, setShowEditRowDialog] = useState(false)
  const [editRow, setEditRow] = useState<EvalsRow | undefined>(undefined)
  const [importErrors, setImportErrors] = useState<string[]>([])

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const emitEvent = () => {
    sendClickAnalyticsEvent({
      category: 'github_models_repo_integration',
      action: 'click_compare_run',
    })
  }
  const handleRun = () => {
    manager.setError(undefined)
    manager.startEvalsRun(
      modelClient,
      models,
      prompts,
      enabledRows,
      evaluators.map(x => x.config),
      editablePromptAndIndex?.[0]?.responseFormat || prompts[0].responseFormat,
      editablePromptAndIndex?.[0]?.jsonSchema || prompts[0].jsonSchema,
    )
    emitEvent()
  }

  const location = useLocation()
  const runSample = useMemo(() => location.search.includes('sample'), [location.search])
  const sampleRan = useRef<boolean>(false)

  useEffect(() => {
    if (models.length > 0 && rows.length === 0 && isNewPrompt && runSample && !sampleRan.current) {
      sampleRan.current = true

      // Remove the default empty prompt
      manager.removePrompt(0)

      const samplePromptsList = samplePrompts(models.map(model => model.name))
      for (const prompt of samplePromptsList) {
        manager.addPrompt(prompt)
      }
      for (const row of sampleRows) {
        manager.evalsAddOrUpdateRow(row)
      }
    }
  }, [models, rows.length, isNewPrompt, runSample, manager])

  const handleStop = useCallback(() => {
    manager.stopEvalsRun()
  }, [manager])

  const handleEditRow = useCallback((row: EvalsRow) => {
    setEditRow(row)
    setShowEditRowDialog(true)
  }, [])

  const [editablePromptAndIndex, setEditablePromptAndIndex] = useState<[PromptConfig, number] | undefined>(undefined)
  const [promptEditorDialogOpen, setPromptEditorDialogOpen] = useState(false)
  const handlePromptEdit = (prompt: PromptConfig, index: number) => {
    setEditablePromptAndIndex([prompt, index])
    setPromptEditorDialogOpen(true)
  }

  const handlePromptModelSelection = useCallback(
    (model: RepoModel, promptIndex: number) => {
      const existingPrompt = prompts[promptIndex]
      if (existingPrompt) manager.updatePrompt({...existingPrompt, model: promptModelIdentifierFor(model)}, promptIndex)
    },
    [manager, prompts],
  )

  const [addPromptDialogOpen, setAddPromptDialogOpen] = useState(false)
  const handlePromptAdd = () => {
    setAddPromptDialogOpen(true)
  }

  const handlePromptFork = () => {
    manager.forkPrompt()
  }

  const handlePromptAdded = (prompt: PromptConfig) => {
    manager.addPrompt(prompt)
    setAddPromptDialogOpen(false)
  }

  const importRowsRef = useRef<{triggerImport: () => void}>(null)

  const promptToCommit = useMemo(() => {
    const currentPrompt = mode === 'review' ? prompts[1]! : prompts[0]
    // row data is tracked in the row state, not in the prompt manager, so we need to make sure the prompt we send to
    // the web commit dialog has the up-to-date test data
    const currentVariables = referencedVariablesInPrompt(currentPrompt)
    currentVariables.push(VariableExpected) // 'expected' is always included in the test data, since evaluators expect it

    const rowsToCommit = filterAndCleanRowVariables(rows, currentVariables)

    return {...currentPrompt, testData: rowsToCommit, evaluators}
  }, [mode, prompts, rows, evaluators])

  const columnCount = prompts.length + 1 // +1 for the input column
  const columnMaxWidth = `${100 / columnCount}%`

  if (runSample && !sampleRan.current) {
    // This prevents the blank slate from showing when the models are loading
    return (
      <div className="flex-1 d-flex flex-column flex-justify-center flex-items-center">
        <Spinner />
        <div className="mt-2">Loading sample data...</div>
      </div>
    )
  }

  return (
    <>
      {(dialogState === 'pending' || dialogState === 'saving') && (
        <PromptWebCommitDialog
          activePrompt={promptToCommit}
          dialogState={dialogState}
          setDialogState={setDialogState}
        />
      )}

      {promptEditorDialogOpen && editablePromptAndIndex && (
        <PromptEditorDialog
          prompt={editablePromptAndIndex[0]}
          onSave={promptConfig => {
            const editablePromptIndex = editablePromptAndIndex[1]
            manager.updatePrompt(promptConfig, editablePromptIndex)
            setEditablePromptAndIndex([promptConfig, editablePromptIndex])
            setPromptEditorDialogOpen(false)
          }}
          onClose={() => {
            setEditablePromptAndIndex(undefined)
            setPromptEditorDialogOpen(false)
          }}
        />
      )}

      {addPromptDialogOpen && (
        <PromptEditorDialog
          title="Add prompt"
          primaryLabel="Add prompt"
          onSave={handlePromptAdded}
          onClose={() => setAddPromptDialogOpen(false)}
        />
      )}

      {showAddRowDialog && <RowEditDialog setShowRowDialog={setShowAddRowDialog} />}
      {showEditRowDialog && <RowEditDialog setShowRowDialog={setShowEditRowDialog} row={editRow} />}

      <ImportRows ref={importRowsRef} setImportError={setImportErrors} rowCount={rows.length} />

      <PromptLayout fullscreen={mode === 'review'}>
        {error && <Banner title={error} variant="warning" className="mb-2" />}
        {importErrors.length > 0 && (
          <Banner
            title={'Something went wrong'}
            description={
              <>
                Unable to import all rows due to:
                <ul className="ml-4">
                  {importErrors.map(errorMessage => (
                    <li key={errorMessage}>{errorMessage}</li>
                  ))}
                </ul>
              </>
            }
            variant="warning"
            className="mb-2"
            onDismiss={() => setImportErrors([])}
          />
        )}
        {mode === 'review' ? (
          <ReviewPromptHeader canCommit={!!isDirty} setDialogState={setDialogState} />
        ) : (
          <PromptFileHeader isDirty={isDirty} prompt={prompts[0]} setDialogState={setDialogState} />
        )}
        <Stack>
          <div className="d-flex flex-justify-between flex-items-start flex-md-items-center flex-column flex-md-row">
            {mode !== 'review' && <ViewSwitcher />}
            {/* Spacer */}
            <div className="flex-1" />
            <Stack direction="horizontal" gap="condensed">
              {mode === 'review' && (
                <CompareRunButton
                  className="ml-2"
                  isRunning={isRunning}
                  canRun={runButtonEnabled}
                  tooltipText={runButtonTooltip}
                  handleStop={handleStop}
                  handleRun={handleRun}
                />
              )}
              {mode !== 'review' && <ClearSessionButton disabled={!(rows.length > 0 || evaluators.length > 0)} />}
              <CommitButton
                canEdit={canEdit}
                isDirty={isDirty}
                promptConfig={prompts[0]}
                setDialogState={setDialogState}
                size="small"
              />
              {mode !== 'review' && (
                <CompareRunButton
                  isRunning={isRunning}
                  canRun={runButtonEnabled}
                  tooltipText={runButtonTooltip}
                  handleStop={handleStop}
                  handleRun={handleRun}
                />
              )}
            </Stack>
          </div>

          <Stack gap="normal">
            <PromptsTable
              prompts={prompts}
              onPromptEdit={handlePromptEdit}
              onModelSelect={handlePromptModelSelection}
              mode={mode}
              columnMaxWidth={columnMaxWidth}
              renderEvaluatorsConfig={evaluators.length > 0 ? <EvaluatorOutlet /> : null}
            />

            <Stack direction="horizontal" justify="end" gap="condensed">
              <AddPromptMenu totalPrompts={prompts.length} onAdd={handlePromptAdd} onFork={handlePromptFork} />
              <AddEvaluatorButton />
            </Stack>

            <DatasetTable
              prompts={prompts}
              columnMaxWidth={columnMaxWidth}
              inputs={rows}
              result={result}
              isRunning={isRunning}
              compare={compare}
              onAdd={() => setShowAddRowDialog(true)}
              onEdit={handleEditRow}
            />

            <AddCompareRowsControls
              totalRows={rows.length}
              onAddRow={() => setShowAddRowDialog(true)}
              onImportRows={() => {
                importRowsRef.current?.triggerImport()
              }}
            />
          </Stack>
        </Stack>
      </PromptLayout>
    </>
  )
}

const samplePrompts = (models: string[]): PromptConfig[] => [
  {
    model: models[0] || '',
    messages: [
      getSystemMessage(
        'You specialize in extracting and organizing key information from expense receipts. Your job is to carefully review each receipt and create a polished, easy-to-read summary. Include details such as the vendor, transaction date, total cost, and a breakdown of categorized expenses. Focus on accuracy and professionalism while keeping the summary brief and informative.',
      ),
      getUserMessage('Summarize this receipt: {{input}}'),
    ],
  },
  {
    model: models[1] || models[0] || '',
    messages: [
      getSystemMessage(
        'You are a expert at summarizing expense receipts. Your task is to analyze a provided receipt and generate a concise summary, including key details like the total amount, vendor name, date, and categorized expenses. Always ensure the summary is accurate, clear, and formatted professionally.',
      ),
      getUserMessage('Summarize this receipt: {{input}}'),
    ],
  },
  {
    model: models[2] || models[1] || models[0] || '',
    messages: [
      getSystemMessage(
        'You specialize in reviewing and summarizing expense receipts with precision and clarity. Your task is to extract and present the most important details from a provided receipt, such as the merchant, transaction date, total cost, and any categorized expenses listed. Ensure the summary is concise, easy to read, and formatted in a way that supports financial organization and reporting.',
      ),
      getUserMessage('Summarize this receipt: {{input}}'),
    ],
  },
]

const sampleRows: EvalsRow[] = [
  {
    id: '0',
    input: `Vendor Information:
Downtown Café & Catering, 789 Elm St, Seattle, WA 98104
Phone: (555) 987-6543
Email: catering@downtowncafe.com
Tax ID: 12-345678

Order Summary:
Date: January 6, 2025
Time: 11:45 AM
Order Number: DC-56789
Server: Mary Johnson

Items Purchased:
	1.	Sandwich Platter for 8 People
	•	Description: Includes a variety of deli sandwiches with turkey, ham, roast beef, and vegetarian options. Comes with sides of chips and pickles.
	•	Quantity: 1
	•	Price Per Platter: $72.00
	•	Line Total: $72.00
	2.	Bottled Water (16 oz)
	•	Description: Individually packaged bottled water for single use.
	•	Quantity: 8
	•	Unit Price: $2.00
	•	Line Total: $16.00
	3.	Coffee Box (96 oz)
	•	Description: Freshly brewed coffee in a to-go box with disposable cups, lids, and creamers.
	•	Quantity: 1
	•	Unit Price: $22.00
	•	Line Total: $22.00

Charges:
Food & Beverage Subtotal: $110.00
Sales Tax (9%): $9.90
Service Charge: $10.00
Tip: $15.00
Grand Total: $144.90

Payment Information:
Payment Method: ACH Transfer from Business Account
Reference Number: 9876543210

Additional Notes:
This order was placed for a team lunch during an extended strategy meeting. Special requests included extra vegetarian options in the sandwich platter and additional creamers for the coffee box. Delivery was made to the conference room on the 12th floor at 10:30 AM.`,
  },
  {
    id: '1',
    input: `Vendor Information:
Sunrise Deli & Bakery, 2145 Maple Ave, Portland, OR 97205
Phone: (555) 321-6789
Email: orders@sunrisedeli.com
Tax ID: 98-7654321

Order Summary:
Date: February 12, 2025
Time: 9:15 AM
Order Number: SD-14987
Server: Carlos Martinez

Items Purchased:

Continental Breakfast Tray
• Description: Selection of fresh bagels, muffins, croissants, and Danish pastries. Served with cream cheese, jam, and butter.
• Quantity: 1
• Price Per Tray: $58.00
• Line Total: $58.00

Fresh Fruit Platter (Serves 10)
• Description: Assorted fresh seasonal fruit, sliced and artfully arranged.
• Quantity: 1
• Unit Price: $36.00
• Line Total: $36.00

Freshly Squeezed Orange Juice (12 oz)
• Description: Single-serve bottles of freshly squeezed orange juice.
• Quantity: 10
• Unit Price: $3.50
• Line Total: $35.00

Charges:
Food & Beverage Subtotal: $129.00
Sales Tax (8.5%): $10.97
Service Charge: $8.00
Tip: $15.00
Grand Total: $162.97

Payment Information:
Payment Method: Company Credit Card
Reference Number: 202502120918

Additional Notes:
Breakfast delivery for team offsite kickoff event. Special requests included gluten-free bagel substitutes and napkin/utensil sets for each guest. Delivered to main entrance at 8:45 AM as requested.`,
  },
]
