import type {Model} from '@github-ui/marketplace-common'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {
  AiModelIcon,
  DownloadIcon,
  KebabHorizontalIcon,
  NoteIcon,
  PencilIcon,
  PlusIcon,
  TrashIcon,
  UploadIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, IconButton, Label, VisuallyHidden} from '@primer/react'
import {Banner, DataTable} from '@primer/react/experimental'
import {useQuery} from '@github-ui/react-query'
import React, {useCallback, useState} from 'react'
import {GiveFeedback} from '../../../components/GiveFeedback'
import type {EvalsRow, EvaluatorState} from '../../../types'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import {usePromptEvalsState} from '../contexts/PromptEvalsStateContext'
import type {EvaluatorCfg} from '../evals-sdk/config'
import type {EvaluationResult} from '../evals-sdk/evaluator/evaluator'
import {EvaluatorTemplateCategories, type EvaluatorTemplate} from '../evaluator-template'
import {GroupedEvaluatorTemplates} from '../evaluators'
import {useExportImportSession} from '../hooks/use-export-import-session'
import {usePromptEvalsManager} from '../prompt-evals-manager'
import styles from './Evals.module.css'
import {EvaluatorDialog} from './evaluators/EvaluatorDialog'
import {Header} from './Header'
import {ImportRows} from './ImportRows'
import {RowDialog} from './RowDialog'
import {ViewSwitcher} from './ViewSwitcher'

export type EvalsProps = {
  modelClient: AzureModelClient
}

type DataRow = {
  id: number
  data: {[variable: string]: string}
  completion?: string
  result?: EvaluationResult[]
}

export function Evals({modelClient}: EvalsProps) {
  const manager = usePromptEvalsManager()

  // We need to potentially prompt different models from the evals experience. The way our current client
  // is written, we need the model catalog data to decide how to prompt the model. So we are fetching all of the
  // model here when entering the evals experience. The data is cached, so other experiences (ModelPicker/Switcher)
  // will be able to use it. ModelSwitcher fetches this data anyway, so this doesn't add any additional load.
  const {data: models, isLoading: isLoadingModels} = useQuery<Model[]>({
    queryKey: ['github-models', 'models'],
    initialData: [],
    async queryFn() {
      const res = await verifiedFetchJSON('/marketplace/models')
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
  })

  const {systemPrompt, prompt, evals, model, error} = usePromptEvalsState()
  const {gettingStarted, modelInputSchema, catalogData} = model
  const {isRunning, rows, evaluators, result} = evals

  const [showAddRowDialog, setShowAddRowDialog] = useState(false)
  const [showEditRowDialog, setShowEditRowDialog] = useState(false)
  const [editRow, setEditRow] = useState<EvalsRow | undefined>(undefined)
  const [importErrors, setImportError] = useState<string[]>([])
  const handleRun = () => {
    manager.setError(undefined)
    manager.startEvalsRun(
      model,
      modelClient,
      models,
      systemPrompt,
      prompt,
      rows,
      evaluators.map(x => x.config),
    )
  }

  const handleStop = useCallback(() => {
    manager.stopEvalsRun()
  }, [manager])

  const [addEvaluatorTemplate, setAddEvaluatorTemplate] = useState<EvaluatorTemplate | undefined>(undefined)
  const [editEvaluatorIndex, setEditEvaluatorIndex] = useState<number | undefined>(undefined)
  const [editEvaluator, setEditEvaluator] = useState<EvaluatorCfg | undefined>(undefined)
  const [evaluatorDialogOpen, setEvaluatorDialogOpen] = useState(false)

  const handleEvalAdd = useCallback(
    (et: EvaluatorTemplate) => {
      if (et.readonly) {
        // Template cannot be customized, add directly
        manager.evalsAddEvaluator({
          config: et.configTemplate,
          readonly: true,
        })
        return
      }

      setAddEvaluatorTemplate(et)
      setEvaluatorDialogOpen(true)
    },
    [setAddEvaluatorTemplate, setEvaluatorDialogOpen, manager],
  )

  const handleEvalEdit = useCallback(
    (index: number, e: EvaluatorCfg) => {
      setEditEvaluatorIndex(index)
      setEditEvaluator(e)
      setEvaluatorDialogOpen(true)
    },
    [setEditEvaluator, setEvaluatorDialogOpen],
  )

  const handleEvalRemove = useCallback(
    (index: number) => {
      manager.evalsRemoveEvaluator(index)
    },
    [manager],
  )

  const handleEditRow = (row: EvalsRow) => {
    setEditRow(row)
    setShowEditRowDialog(true)
  }

  const dataRows: DataRow[] = rows.map((row, index) => {
    const id = row.id

    // TODO: Better matching than via index
    const resultRow = result?.[index]

    return {
      id,
      data: row,
      completion: resultRow?.completion || undefined,
      result: resultRow?.evals,
    }
  })

  const canRun = !isLoadingModels && !!prompt

  const [actionsMenuOpen, setActionsMenuOpen] = useState(false)

  const {exportSession, importSession, fileInputRef} = useExportImportSession(
    manager,
    model,
    systemPrompt,
    prompt,
    rows,
    evals.evaluators.map(x => x.config),
    () => {
      // When importing, ensure the menu is closed after the user has selected
      // a file to import.
      setActionsMenuOpen(false)
    },
  )

  return (
    <div className={styles.header}>
      {evaluatorDialogOpen && (
        <EvaluatorDialog
          template={addEvaluatorTemplate}
          evaluatorIndex={editEvaluatorIndex}
          evaluator={editEvaluator}
          onClose={() => {
            setAddEvaluatorTemplate(undefined)
            setEditEvaluator(undefined)
            setEvaluatorDialogOpen(false)
          }}
        />
      )}

      <div className={styles.mobileFeedback}>
        <GiveFeedback mobile />
      </div>
      <div className={styles.container}>
        <Header
          run={handleRun}
          stop={handleStop}
          canRun={canRun}
          running={isRunning}
          model={catalogData}
          modelInputSchema={modelInputSchema}
          gettingStarted={gettingStarted}
        />
        {error && <Banner title={error} variant="critical" className="mb-2" />}
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
            onDismiss={() => setImportError([])}
          />
        )}
        <div className="flex-1 d-flex flex-column border rounded-2 overflow-hidden">
          <div className="d-flex flex-column flex-md-row position-sticky top-0 p-2 border-bottom bgColor-muted flex-items-start flex-md-items-center gap-2">
            <ViewSwitcher model={catalogData} />
            <div className="hide-sm" style={{width: '1px', height: '20px', background: 'var(--borderColor-default'}} />
            <div className="d-flex flex-justify-between flex-md-justify-start flex-auto">
              <ImportRows setImportError={setImportError} />
              <Button className="ml-2" size="small" leadingVisual={PlusIcon} onClick={() => setShowAddRowDialog(true)}>
                Add row
              </Button>
            </div>
            {showAddRowDialog && <RowDialog setShowRowDialog={setShowAddRowDialog} />}
            {showEditRowDialog && <RowDialog setShowRowDialog={setShowEditRowDialog} row={editRow} />}
            <div className="d-flex flex-justify-between">
              <div className="flex-1" />
              <ActionMenu>
                <ActionMenu.Button size="small">Add test criteria</ActionMenu.Button>
                <ActionMenu.Overlay width="medium">
                  <ActionList>
                    {Object.entries(GroupedEvaluatorTemplates).map(([category, templates]) => {
                      return (
                        <ActionList.Group key={category} auxiliaryText="test">
                          <ActionList.GroupHeading>
                            {EvaluatorTemplateCategories[category]!.name}
                          </ActionList.GroupHeading>
                          {templates.map(et => (
                            <ActionList.Item key={et.displayName} onSelect={() => handleEvalAdd(et)}>
                              <ActionList.LeadingVisual>
                                {React.createElement(et.icon || AiModelIcon)}
                              </ActionList.LeadingVisual>
                              {et.displayName}
                              <ActionList.Description variant="block">{et.description}</ActionList.Description>
                            </ActionList.Item>
                          ))}
                        </ActionList.Group>
                      )
                    })}
                  </ActionList>
                </ActionMenu.Overlay>
              </ActionMenu>
              <ActionMenu open={actionsMenuOpen} onOpenChange={x => setActionsMenuOpen(x)}>
                <ActionMenu.Button className="ml-2" icon={KebabHorizontalIcon} size="small" aria-label="Actions">
                  <></>
                </ActionMenu.Button>
                <ActionMenu.Overlay width="medium">
                  <ActionList>
                    <ActionList.Group>
                      <ActionList.Item
                        onSelect={() => manager.evalsClear()}
                        disabled={rows.length === 0 && evaluators.length === 0}
                      >
                        <ActionList.LeadingVisual>
                          <TrashIcon />
                        </ActionList.LeadingVisual>
                        Clear session
                      </ActionList.Item>
                    </ActionList.Group>

                    <input
                      ref={fileInputRef}
                      type="file"
                      accept={['text/yaml'].join(',')}
                      multiple={false}
                      hidden
                      onChange={importSession}
                    />
                    <ActionList.Group>
                      <ActionList.Item
                        onSelect={e => {
                          e.preventDefault()
                          fileInputRef.current?.click()
                        }}
                      >
                        <ActionList.LeadingVisual>
                          <DownloadIcon />
                        </ActionList.LeadingVisual>
                        Import session
                      </ActionList.Item>
                      <ActionList.Item onSelect={exportSession}>
                        <ActionList.LeadingVisual>
                          <UploadIcon />
                        </ActionList.LeadingVisual>
                        Export session
                      </ActionList.Item>
                    </ActionList.Group>
                  </ActionList>
                </ActionMenu.Overlay>
              </ActionMenu>
            </div>
          </div>

          <div className={styles['eval-grid']}>
            <DataTable
              data={dataRows}
              columns={[
                // Dataset columns
                {
                  id: 'input',
                  renderCell: row => <>{row.data.input}</>,
                  header: 'input',
                  maxWidth: '30%',
                },
                {
                  id: 'expected',
                  renderCell: row => <>{row.data.expected}</>,
                  header: 'expected',
                  maxWidth: '30%',
                },
                // Hard-coded output column
                {
                  id: 'output',
                  renderCell: row => <>{row.completion || null}</>,
                  header: 'Output',
                  maxWidth: '30%',
                },
                // Evaluators
                ...evaluators.map((e, i) => ({
                  id: `evaluator-${i}`,
                  renderCell: EvaluatorCell.bind(undefined, i),
                  header: () => (
                    <EvaluatorColumnHeader
                      e={e}
                      index={i}
                      onRemove={handleEvalRemove}
                      onEdit={() => handleEvalEdit(i, e.config)}
                    />
                  ),
                })),
                // Actions
                {
                  id: 'action',
                  header: () => <VisuallyHidden>Actions</VisuallyHidden>,
                  renderCell: row => {
                    return (
                      <>
                        <IconButton
                          aria-label={`Edit`}
                          icon={PencilIcon}
                          variant="invisible"
                          onClick={() => {
                            handleEditRow({...row.data, id: row.id} as EvalsRow)
                          }}
                        />
                        <IconButton
                          aria-label={`Delete`}
                          icon={TrashIcon}
                          variant="invisible"
                          onClick={() => {
                            manager.evalsRemoveRow(row.id)
                          }}
                        />
                      </>
                    )
                  },
                },
              ]}
            />
          </div>
        </div>
      </div>
    </div>
  )
}

function EvaluatorCell(index: number, row: DataRow) {
  // Lookup result for row and evaluator
  const r = row.result?.[index]

  if (!r) {
    return null
  }

  if (r.error) {
    return <span>{r.error}</span>
  }

  // Always map scores to pass/fail for now
  if (r.pass !== undefined) {
    return r.pass ? <Label variant="success">Pass</Label> : <Label variant="danger">Fail</Label>
  }

  if (r.score !== undefined) {
    const scoreColor = getScoreColor(r.score)
    const labelClasses = `fgColor-${scoreColor.color} borderColor-${scoreColor.borderColor}`
    return <Label className={labelClasses}>{r.score * 100.0}%</Label>
  }

  return null
}

function getScoreColor(score: number): {color: string; borderColor: string} {
  switch (true) {
    case score >= 0 && score < 0.25:
      return {
        color: 'danger',
        borderColor: 'danger-emphasis',
      }
    case score >= 0.25 && score < 0.5:
      return {
        color: 'severe',
        borderColor: 'severe-emphasis',
      }
    case score >= 0.5 && score < 0.75:
      return {
        color: 'attention',
        borderColor: 'attention-emphasis',
      }
    case score >= 0.75:
      return {
        color: 'success',
        borderColor: 'success-emphasis',
      }
  }

  return {
    color: 'muted',
    borderColor: 'default',
  }
}

function EvaluatorColumnHeader({
  e,
  index,
  onEdit,
  onRemove,
}: {
  e: EvaluatorState
  index: number
  onEdit: (e: EvaluatorState) => void
  onRemove: (index: number) => void
}) {
  return (
    <div className="d-flex flex-items-center flex-1">
      <div className="flex-1 d-flex flex-items-center">
        <div className="mr-1">
          <NoteIcon />
        </div>
        {e.config.name}
      </div>
      {!e.readonly && (
        <IconButton
          size="small"
          variant="invisible"
          icon={PencilIcon}
          aria-label="Edit"
          onClick={() => onEdit(e)}
          className="mr-1"
        />
      )}
      <IconButton
        size="small"
        variant="invisible"
        icon={TrashIcon}
        aria-label="Remove"
        onClick={() => onRemove(index)}
      />
    </div>
  )
}
