import type {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {
  KebabHorizontalIcon,
  PencilIcon,
  PlayIcon,
  PlusIcon,
  RepoForkedIcon,
  SquareFillIcon,
  TrashIcon,
  UploadIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, IconButton} from '@primer/react'
import {Banner, DataTable} from '@primer/react/experimental'
import {Suspense, lazy, useCallback, useRef, useState} from 'react'
import {useLocation} from 'react-router-dom'
import {useModels} from '../contexts/ModelsContext'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import {usePromptCompareManager} from '../prompt-compare-manager'
import type {RowPromptResult} from '../prompt-compare-state'
import type {PromptConfig} from '../prompts'
import type {EvalsRow} from '../types'
import styles from './Compare.module.css'
import {EvaluatorBar} from './EvaluatorBar'
import {EvaluatorCell} from './EvaluatorCell'
import {ImportRows} from './ImportRows'
import {InlinePrompt} from './InlinePrompt'
import {PromptEditorDialog} from './PromptEditorDialog'
import {PromptFileHeader} from './PromptFileHeader'
import {RowEditDialog} from './RowEditDialog'
import {ViewSwitcher} from './ViewSwitcher'
import {PromptLayout} from './PromptLayout'

// Lazy load as WebCommitDialog is not compatible with SSR
const WebCommitDialog = lazy(async () => {
  const module = await import('@github-ui/web-commit-dialog')
  return {default: module.WebCommitDialog}
})

export type CompareProps = {
  modelClient: AzureModelClient

  mode: 'compare' | 'pr-compare'
}

type DataRow = {
  id: string
  data: {[variable: string]: string}

  result?: RowPromptResult[]
}

export function Compare({modelClient, mode = 'compare'}: CompareProps) {
  const manager = usePromptCompareManager()

  const {error, prompts, compare, isDirty} = usePromptCompareState()
  const {isRunning, rows, evaluators, result} = compare
  const canRun =
    compare.rows?.length > 0 &&
    prompts.length > 0 &&
    prompts.some(p => !!p.model && !!p.messages && p.messages.length > 0 && p.messages.some(m => !!m.message.trim()))

  const models = useModels()

  const [showAddRowDialog, setShowAddRowDialog] = useState(false)
  const [showEditRowDialog, setShowEditRowDialog] = useState(false)
  const [editRow, setEditRow] = useState<EvalsRow | undefined>(undefined)
  const [importErrors, setImportErrors] = useState<string[]>([])
  const handleRun = () => {
    manager.setError(undefined)
    manager.startEvalsRun(
      modelClient,
      models,
      prompts,
      rows,
      evaluators.map(x => x.config),
    )
  }

  const handleStop = useCallback(() => {
    manager.stopEvalsRun()
  }, [manager])

  const handleEditRow = (row: EvalsRow) => {
    setEditRow(row)
    setShowEditRowDialog(true)
  }

  const dataRows: DataRow[] = rows.map((row, index) => {
    const id = row.id

    const resultRow = result?.[index]

    return {
      id,
      data: row,
      result: resultRow,
    }
  })

  const [actionsMenuOpen, setActionsMenuOpen] = useState(false)
  const [commitOpen, setCommitOpen] = useState(false)

  const [editablePrompt, setEditablePrompt] = useState<[PromptConfig, number] | undefined>(undefined)
  const [promptEditorDialogOpen, setPromptEditorDialogOpen] = useState(false)
  const handlePromptEdit = (prompt: PromptConfig, index: number) => {
    setEditablePrompt([prompt, index])
    setPromptEditorDialogOpen(true)
  }

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

  const location = useLocation()
  const ref = new URLSearchParams(location.search).get('compare') || 'main' // TODO: HACK!

  return (
    <>
      {commitOpen && (
        <Suspense fallback={<div>Loading</div>}>
          <WebCommitDialog
            dialogProps={{}}
            description="Updated"
            dialogState="pending"
            isQuickPull={false}
            helpUrl="https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/committing-changes-to-your-project"
            message="Updated prompt"
            onSave={() => {}}
            refName={ref}
            disableQuickPull
            // setPRTargetBranch={}
            setAuthorEmail={() => {}}
            setDescription={() => {}}
            setMessage={() => {}}
            setDialogState={() => {
              setCommitOpen(false)
            }}
            webCommitInfo={{
              authorEmails: ['cschleiden@live.de'],
              canCommitStatus: 'allowed',
              dcoSignoffEnabled: false,
              defaultEmail: 'cschleiden@live.de',
              defaultNewBranchName: 'patch-1',
              commitOid: '123',
              lockedOnMigration: false,
              shouldFork: false,
              repoHeadEmpty: false,
              saveUrl: '',
              suggestionsUrlEmoji: '',
              suggestionsUrlMention: '',
              suggestionsUrlIssue: '',
              shouldUpdate: true,
              pr: '',
            }}
            fileStatuses={{[prompts[0]!.path!]: 'M'}}
          />
        </Suspense>
      )}

      {promptEditorDialogOpen && editablePrompt && (
        <PromptEditorDialog
          prompt={editablePrompt[0]}
          onSave={promptConfig => {
            manager.updatePrompt(promptConfig, editablePrompt[1])
            setPromptEditorDialogOpen(false)
          }}
          onClose={() => {
            setEditablePrompt(undefined)
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

      <ImportRows ref={importRowsRef} setImportError={setImportErrors} />

      <PromptLayout>
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
            onDismiss={() => setImportErrors([])}
          />
        )}
        <PromptFileHeader prompt={prompts[0]!} canCommit={!!isDirty} setCommitOpen={x => setCommitOpen(x)} />
        <div className="border rounded-2 flex-1 d-flex flex-column overflow-hidden">
          <div className="d-flex flex-justify-between p-2 border-bottom bgColor-muted flex-items-center">
            {mode !== 'pr-compare' && <ViewSwitcher />}
            {/* Spacer */}
            <div className="flex-1" />
            <ActionMenu>
              <ActionMenu.Button leadingVisual={PlusIcon} size="small">
                Add rows
              </ActionMenu.Button>
              <ActionMenu.Overlay width="medium">
                <ActionList>
                  <ActionList.Item onSelect={() => setShowAddRowDialog(true)}>
                    <ActionList.LeadingVisual>
                      <PlusIcon />
                    </ActionList.LeadingVisual>
                    Add row
                  </ActionList.Item>
                  <ActionList.Item
                    onSelect={() => {
                      importRowsRef.current?.triggerImport()
                    }}
                  >
                    <ActionList.LeadingVisual>
                      <UploadIcon />
                    </ActionList.LeadingVisual>
                    Import rows
                  </ActionList.Item>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
            {mode === 'pr-compare' && (
              <>
                {isRunning ? (
                  <Button
                    className="ml-2"
                    size="small"
                    leadingVisual={SquareFillIcon}
                    variant="danger"
                    onClick={handleStop}
                  >
                    Stop
                  </Button>
                ) : (
                  <Button className="ml-2" size="small" leadingVisual={PlayIcon} variant="primary" onClick={handleRun}>
                    Run
                  </Button>
                )}
              </>
            )}
            <ActionMenu open={actionsMenuOpen} onOpenChange={x => setActionsMenuOpen(x)}>
              <ActionMenu.Button className="mx-2" icon={KebabHorizontalIcon} size="small" aria-label="Actions" />
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
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
            {mode !== 'pr-compare' &&
              (isRunning ? (
                <Button size="small" leadingVisual={SquareFillIcon} variant="danger" onClick={handleStop}>
                  Stop
                </Button>
              ) : (
                <Button
                  size="small"
                  leadingVisual={PlayIcon}
                  variant="primary"
                  disabled={!canRun}
                  onClick={() => handleRun(/*variables*/)}
                >
                  Run
                </Button>
              ))}
          </div>
          <EvaluatorBar />
          <div className={styles['eval-grid']}>
            <DataTable
              data={[
                // Initial row with the prompts
                {
                  id: 0,
                  type: 'prompts',
                  data: null,
                  results: undefined,
                },
                // Second header row
                {
                  id: 1,
                  type: 'results-header',
                  data: null,
                },
                ...dataRows.map(r => ({
                  id: 100 + r.id,
                  type: 'result',
                  data: r.data,
                  result: r.result,
                })),
              ]}
              columns={[
                {
                  id: 'input',
                  header: '',
                  maxWidth: `${100 / (1 + prompts.length)}%`,
                  rowHeader: true,
                  // TODO determine a better type here
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  renderCell: (row: any) => {
                    if (row.type === 'prompts') {
                      return null
                    }

                    if (row.type === 'results-header') {
                      return <code className="color-fg-muted">{'{{input}}'}</code>
                    }

                    return (
                      <div className="d-flex flex-items-start">
                        <div className="flex-1">{row?.data?.['input']}</div>
                        <IconButton
                          icon={PencilIcon}
                          variant="invisible"
                          aria-label="Edit row"
                          onClick={() =>
                            handleEditRow({
                              id: row.id,
                              ...row.data,
                            })
                          }
                        />
                      </div>
                    )
                  },
                },
                // Render prompt columns
                ...prompts.map((prompt, index) => ({
                  id: `prompt-${index}`,
                  header: () => {
                    if (mode !== 'pr-compare') {
                      if (index === 0) {
                        return 'Original'
                      } else {
                        return `Prompt ${index}`
                      }
                    }

                    // TODO: CS: Get actual commit details here..
                    if (index === 0) {
                      return (
                        <div>
                          <span className="color-fg-default mr-2">Original</span>
                          <span className="color-fg-muted text-small">init commit</span>
                        </div>
                      )
                    } else {
                      return (
                        <div>
                          <span className="color-fg-default mr-2">Proposed</span>
                          <span className="color-fg-muted text-small">update prompt</span>
                        </div>
                      )
                    }
                  },
                  maxWidth: `${100 / (1 + prompts.length)}%`,
                  // TODO determine a better type here
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  renderCell: (row: any) => {
                    if (row.type === 'prompts') {
                      return (
                        <InlinePrompt
                          prompt={prompt}
                          renderActions={() => (
                            <>
                              {/* Can only edit the original prompt if we aren't comparing */}
                              {(index > 0 || mode !== 'pr-compare') && (
                                <IconButton
                                  icon={PencilIcon}
                                  aria-label="Edit prompt"
                                  variant="invisible"
                                  onClick={() => handlePromptEdit(prompt, index)}
                                />
                              )}
                              {index > 0 ? (
                                <IconButton
                                  icon={TrashIcon}
                                  aria-label="Remove prompt"
                                  variant="invisible"
                                  onClick={() => manager.removePrompt(index)}
                                />
                              ) : null}
                            </>
                          )}
                        />
                      )
                    }

                    if (row.type === 'results-header') {
                      return <span className="color-fg-muted">Output</span>
                    }

                    if (row.type === 'result') {
                      const rowResult: RowPromptResult | undefined = row.result?.[index]
                      if (!rowResult) {
                        return null
                      }

                      const completions = rowResult.completions
                      const evalResults = rowResult.evals

                      return (
                        <div>
                          {/* Add evaluator results */}
                          <div className="d-flex flex-items-center flex-wrap color-fg-muted text-small mb-1">
                            {compare.evaluators.map((e, eIdx) => {
                              const eResult = evalResults?.[eIdx]
                              if (!eResult) {
                                return null
                              }

                              return (
                                <span key={`e-result-${e.config.name}`}>
                                  {e.config.name}: <EvaluatorCell r={eResult} />
                                  {eIdx < compare.evaluators.length - 1 ? <>,&nbsp;</> : null}
                                </span>
                              )
                            })}
                          </div>
                          {/* TODO: Render multiple completions with better formatting */}
                          {completions.map(c => (
                            <div key={c.message}>{c.message}</div>
                          ))}
                        </div>
                      )
                    }

                    return null
                  },
                })),
                {
                  id: 'add-button',
                  width: 50, // Button is 34px wide + 2*8px padding
                  header: () => {
                    return (
                      <ActionMenu>
                        <ActionMenu.Button size="small" variant="invisible" icon={PlusIcon} aria-label="Add prompt" />
                        <ActionMenu.Overlay>
                          <ActionList>
                            <ActionList.Item onSelect={() => handlePromptFork()}>
                              <ActionList.LeadingVisual>
                                <RepoForkedIcon />
                              </ActionList.LeadingVisual>
                              Fork original prompt
                            </ActionList.Item>
                            <ActionList.Item onSelect={() => handlePromptAdd()}>
                              <ActionList.LeadingVisual>
                                <PlusIcon />
                              </ActionList.LeadingVisual>
                              New prompt
                            </ActionList.Item>
                          </ActionList>
                        </ActionMenu.Overlay>
                      </ActionMenu>
                    )
                  },
                  // Render nothing for the individual cells
                  renderCell: () => null,
                },
              ]}
            />
          </div>
        </div>
      </PromptLayout>
    </>
  )
}
