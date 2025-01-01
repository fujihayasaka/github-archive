import {Box, Button, Dialog, FormControl, Flash, IconButton} from '@primer/react'
import {ArrowLeftIcon, XIcon} from '@primer/octicons-react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useState, useEffect, useCallback, useRef} from 'react'
import type {CopilotChatRepo, GitHubFileFormData} from '../types'
import type {TreeItem} from '@github-ui/repos-file-tree-view'
import type {DirectoryItem} from '@github-ui/code-view-types'
import {useTreeList} from '@github-ui/code-view-shared/hooks/use-tree-list'
import {convertFlatPathsToTreeItems} from '../utils/convert-tree-data'
import {FileTreePicker} from './file-tree-picker/FileTreePicker'
import {RepoSelectPanel} from '@github-ui/copilot-chat/components/RepoSelectPanel'
import {CurrentRepositoryProvider, type Repository} from '@github-ui/current-repository'
import {FileQueryProvider} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {FilesPageInfoProvider} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {AllShortcutsEnabledProvider} from '@github-ui/code-view-shared/contexts/AllShortcutsEnabledContext'
import {testIdProps} from '@github-ui/test-id-props'
import FileResultsList from './files-search/FileResultsList'
import {ReposSelector} from '@github-ui/repos-selector'

import styles from './MultiFilePicker.module.css'

import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'

interface DropdownRepository {
  id: number
  name: string
  enabled: boolean
}
interface Props {
  formData: GitHubFileFormData[]
  onCancel: () => void
  onSave: (data: GitHubFileFormData[]) => Promise<void> | void
  findFileWorkerPath: string
  attachmentButtonRef: React.RefObject<HTMLButtonElement>
  openRepoPanel: boolean
  owner?: string
}

interface FilePickerFormProps {
  currentRepo: CopilotChatRepo
  localFormData: GitHubFileFormData[]
  setLocalFormData: (data: GitHubFileFormData[]) => void
  fetchError: string | null
  onFileCountChange?: (count: number) => void
  processingTime: number
  expandedPath: string
}

const MAXIMUM_FILE_COUNT = 50

function FilePickerForm({
  currentRepo,
  setLocalFormData,
  fetchError,
  onFileCountChange,
  processingTime,
  expandedPath,
}: FilePickerFormProps) {
  const [selectedItems, setSelectedItems] = useState<Set<string>>(() => new Set())
  const [allDirectories, setAllDirectories] = useState<Set<string>>(() => new Set())

  // call useTreeList
  const {list, directories, loading} = useTreeList(currentRepo.commitOID, true)

  const [rootItems, setRootItems] = useState<Array<TreeItem<DirectoryItem>>>([])

  // Update tree items when list or directories change
  useEffect(() => {
    const response = {paths: list, directories}
    const items = convertFlatPathsToTreeItems(response)
    setRootItems(items)
    setAllDirectories(new Set(directories))
  }, [list, directories, setRootItems, currentRepo.commitOID])

  // Track selected files and update form data
  useEffect(() => {
    const files = Array.from(selectedItems).filter(path => !allDirectories.has(path))
    onFileCountChange?.(files.length)

    const newFormData = files.map(path => ({
      id: `${currentRepo.id}-${path}`,
      repositoryId: currentRepo.id,
      nwo: `${currentRepo.ownerLogin}/${currentRepo.name}`,
      filePath: path,
      type: 'github_file' as const,
    }))
    setLocalFormData(newFormData)
  }, [selectedItems, allDirectories, currentRepo, setLocalFormData, onFileCountChange])

  const getItemUrl = useCallback(
    (item: DirectoryItem) =>
      `/${`${currentRepo.name}/${currentRepo.ownerLogin}`}/tree/${currentRepo.refInfo.name}/${item.path}`,
    [currentRepo],
  )

  return (
    <>
      <Box
        sx={{
          flexGrow: 1,
          maxHeight: '100% !important',
          minHeight: '300px',
          overflowY: 'auto',
          scrollbarGutter: 'stable',
          display: 'flex',
          flexDirection: 'column',
        }}
      >
        <FileTreePicker
          rootItems={rootItems}
          expandedPath={expandedPath}
          selectedItemRef={() => {}} // We can skip this for now
          setRootItems={setRootItems}
          navigateOnClick={false}
          directoryNavigateOnClick={false}
          selectedItems={selectedItems}
          onSelectionChange={setSelectedItems}
          processingTime={processingTime}
          loading={loading || false}
          fetchError={!!fetchError}
          getItemUrl={getItemUrl}
          sortDirectoryItems={items => items.sort((a, b) => a.data.name.localeCompare(b.data.name))}
        />
      </Box>
    </>
  )
}

function CloseButton({onClose}: {onClose: () => void}) {
  return <IconButton icon={XIcon} aria-label="Close" onClick={onClose} variant="invisible" />
}

export function MultiFilePicker({
  formData,
  onCancel,
  onSave,
  findFileWorkerPath,
  attachmentButtonRef,
  openRepoPanel,
  owner,
}: Props) {
  const [repoDetailsCache, setRepoDetailsCache] = useState<Record<number, CopilotChatRepo>>({})
  const [fetchError, setFetchError] = useState<string | null>(null)
  const [currentRepo, setCurrentRepo] = useState<CopilotChatRepo | null>(null)
  const [openRepoPicker, setOpenRepoPicker] = useState(openRepoPanel)
  const [localFormData, setLocalFormData] = useState<GitHubFileFormData[]>(formData)
  const [processingTime] = useState(0)
  const [isSaving, setIsSaving] = useState(false)
  const [savingError, setSavingError] = useState<string | null>(null)

  const [expandedPath, setExpandedPath] = useState('')
  const [selectedFileCount, setSelectedFileCount] = useState(0)

  const selectingRepo = useRef(false)

  const fetchRepo = async (repoID: number): Promise<void> => {
    selectingRepo.current = true

    let payload: CopilotChatRepo

    if (repoDetailsCache[repoID]) {
      payload = repoDetailsCache[repoID]
      setCurrentRepo(payload)
      return
    }

    try {
      const res = await verifiedFetchJSON(`/github-copilot/chat/repositories/${repoID}`, {method: 'GET'})

      if (!res.ok) {
        setFetchError(`Failed to fetch repository details: ${res.status}`)
        return
      }

      payload = await res.json()

      setRepoDetailsCache(prev => ({
        ...prev,
        [repoID]: payload,
      }))

      setCurrentRepo(payload)
      setOpenRepoPicker(false)
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An unknown error occurred'
      setFetchError(errorMessage)
    }
    selectingRepo.current = false
  }

  const onSelectRepo = () => {
    setCurrentRepo(null)
    setLocalFormData([])
    setOpenRepoPicker(true)
  }

  function truncatePathsByLength(path: string, maxLength = 30) {
    const truncatedPath = path.length <= maxLength ? path : `...${path.slice(path.length - maxLength, path.length)}`

    // eslint-disable-next-line github/unescaped-html-literal
    return `<b>${truncatedPath}</b>`
  }

  const fileCountExceeded = selectedFileCount > MAXIMUM_FILE_COUNT
  const handleSave = async () => {
    setIsSaving(true)
    if (fileCountExceeded) {
      setIsSaving(false)
      return
    }

    try {
      await onSave(localFormData)
    } catch (error: unknown) {
      let errorMessage = 'An unknown error occurred'

      if (error && typeof error === 'object' && 'base' in error && typeof error.base === 'string') {
        if (error.base.startsWith('unsupported_file_type') && 'files' in error) {
          const unsupportedFiles = error.files as string[]
          if (unsupportedFiles.length === 1) {
            errorMessage = `This file can't be submitted: ${unsupportedFiles[0]}. Only supported file types are allowed.`
          } else {
            const [firstThreeFiles, remainingFiles] = [unsupportedFiles.slice(0, 3), unsupportedFiles.slice(3)]
            errorMessage = `One or more files can't be submitted: `
            errorMessage += firstThreeFiles.map(path => truncatePathsByLength(path)).join(', ')
            if (remainingFiles.length > 0) {
              errorMessage += `, and ${remainingFiles.length} more.`
            } else {
              errorMessage += '.'
            }
            errorMessage += ` Only supported file types are allowed.`
          }
        } else {
          errorMessage = error.base
        }
      }

      if (errorMessage.startsWith('The size of the space exceeds the current limit')) {
        errorMessage = 'The size of the space exceeds the current limit'
      }

      setSavingError(errorMessage)
    } finally {
      setIsSaving(false)
    }
  }

  async function queryForRepos() {
    let query = ''
    if (owner) {
      query = `owner:${owner}`
    }

    const response = await verifiedFetchJSON(`/_filter/repositories?q=${encodeURIComponent(query)}`)
    if (response.ok) {
      const repos = (await response.json()).repositories.map((repo: {id: number; nameWithOwner: string}) => {
        return {name: repo.nameWithOwner, enabled: true, id: repo.id}
      })
      return repos
    }
    return []
  }

  useEffect(() => {
    setSavingError(null)
  }, [localFormData])

  return openRepoPanel ? (
    <>
      <RepoSelectPanel
        selectionVariant="instant"
        open={!currentRepo && openRepoPicker}
        onOpenChange={newOpen => {
          // Ignore while loading repo data in order to avoid flash
          if (!selectingRepo.current) {
            setOpenRepoPicker(newOpen)
            onCancel()
          }
        }}
        selectedRepoIds={new Set()}
        onSelectRepo={async (repoId: number) => {
          if (!repoId) return
          setLocalFormData([])
          await fetchRepo(repoId)
        }}
        cancelReturnFocusRef={attachmentButtonRef}
        submitReturnFocusRef={attachmentButtonRef}
        error={fetchError ?? undefined}
        ownerDisplayLogin={owner}
      />

      {currentRepo && (
        <Dialog
          onClose={onCancel}
          title={`Add files from ${currentRepo.ownerLogin}/${currentRepo.name}`}
          // 600px is the max height of the RepoSelectPanel
          sx={{maxHeight: '600px', '@media screen and (max-width: 768px)': {maxHeight: 'unset'}}}
          width="large"
          position={{narrow: 'fullscreen'}}
          renderHeader={({onClose}) => {
            return (
              <Dialog.Header>
                <div className={styles.dialogHeader}>
                  <IconButton icon={ArrowLeftIcon} aria-label="Back" onClick={onSelectRepo} variant="invisible" />{' '}
                  <Dialog.Title>Select folders and files</Dialog.Title>
                  <CloseButton onClose={() => onClose('close-button')} />
                </div>
                <Dialog.Subtitle className="mt-0">
                  <CurrentRepositoryProvider repository={currentRepo as unknown as Repository}>
                    <FileQueryProvider>
                      <FilesPageInfoProvider
                        refInfo={{
                          name: currentRepo.refInfo.name,
                          canEdit: true,
                          listCacheKey: 'anything',
                          currentOid: currentRepo.commitOID,
                        }}
                        path="test"
                        action="tree"
                        copilotAccessAllowed
                      >
                        <AllShortcutsEnabledProvider allShortcutsEnabled={false}>
                          <FileResultsList
                            commitOid={currentRepo.commitOID}
                            findFileWorkerPath={findFileWorkerPath}
                            onItemSelected={(path?: string) => {
                              if (path) {
                                setExpandedPath(path)
                              }
                            }}
                            config={{
                              enableOverlay: true,
                              disableNavigation: true,
                              searchPlaceholder: 'Search for files or folders',
                              actionText: 'Search for files or folders',
                            }}
                          />
                        </AllShortcutsEnabledProvider>
                      </FilesPageInfoProvider>
                    </FileQueryProvider>
                  </CurrentRepositoryProvider>
                </Dialog.Subtitle>
              </Dialog.Header>
            )
          }}
          renderFooter={() => (
            <Dialog.Footer>
              <div className="d-flex flex-items-center">
                {fileCountExceeded ? (
                  <FormControl.Validation variant="error">
                    Up to {MAXIMUM_FILE_COUNT} files can be added at a time.
                  </FormControl.Validation>
                ) : null}
              </div>
              <div className="d-flex flex-row flex-justify-end gap-2">
                <Button onClick={onCancel}>Cancel</Button>
                <Button
                  {...testIdProps('save-resource-button')}
                  variant="primary"
                  onClick={handleSave}
                  count={isSaving ? undefined : selectedFileCount || undefined}
                  loading={isSaving}
                >
                  Add
                </Button>
              </div>
            </Dialog.Footer>
          )}
          renderBody={() => (
            <div className="d-flex flex-column">
              {fetchError && <span>{fetchError}</span>}
              {savingError && (
                <div className="position-sticky top-0 bgColor-default flash-banner">
                  <Flash full variant="danger">
                    <SafeHTMLText as="span" html={savingError as SafeHTMLString} />
                  </Flash>
                </div>
              )}
              <CurrentRepositoryProvider repository={currentRepo as unknown as Repository}>
                <FileQueryProvider>
                  <FilesPageInfoProvider
                    refInfo={{
                      name: currentRepo.refInfo.name,
                      canEdit: true,
                      listCacheKey: 'anything',
                      currentOid: currentRepo.commitOID,
                    }}
                    path="test"
                    action="tree"
                    copilotAccessAllowed
                  >
                    <div className="p-2">
                      <FilePickerForm
                        expandedPath={expandedPath}
                        currentRepo={currentRepo}
                        localFormData={localFormData}
                        setLocalFormData={setLocalFormData}
                        onFileCountChange={setSelectedFileCount}
                        fetchError={fetchError}
                        processingTime={processingTime}
                      />
                    </div>
                  </FilesPageInfoProvider>
                </FileQueryProvider>
              </CurrentRepositoryProvider>
            </div>
          )}
        />
      )}
    </>
  ) : (
    // Used by custom copilot /share form
    // RepoSelectPanel uses the chatState which is not available in the custom copilot form
    <Dialog
      onClose={onCancel}
      title={currentRepo ? `Add files from ${currentRepo.ownerLogin}/${currentRepo.name}` : 'Add files'}
      sx={{maxHeight: '500px'}}
      renderHeader={({onClose}) => {
        return (
          <Dialog.Header>
            <div className="d-flex flex-justify-between flex-items-center px-2">
              <Dialog.Title>
                {currentRepo ? `Add files from ${currentRepo.ownerLogin}/${currentRepo.name}` : 'Add files'}
              </Dialog.Title>
              <CloseButton onClose={() => onClose('close-button')} />
            </div>
            <Dialog.Subtitle>
              {currentRepo && (
                <CurrentRepositoryProvider repository={currentRepo as unknown as Repository}>
                  <FileQueryProvider>
                    <FilesPageInfoProvider
                      refInfo={{
                        name: currentRepo.refInfo.name,
                        canEdit: true,
                        listCacheKey: 'anything',
                        currentOid: currentRepo.commitOID,
                      }}
                      path="test"
                      action="tree"
                      copilotAccessAllowed
                    >
                      <AllShortcutsEnabledProvider allShortcutsEnabled={false}>
                        <FileResultsList
                          commitOid={currentRepo.commitOID}
                          findFileWorkerPath={findFileWorkerPath}
                          onItemSelected={(path?: string) => {
                            if (path) {
                              setExpandedPath(path)
                            }
                          }}
                          config={{
                            enableOverlay: true,
                            disableNavigation: true,
                            searchPlaceholder: 'Search',
                            actionText: 'Search for files or folders',
                          }}
                        />
                      </AllShortcutsEnabledProvider>
                    </FilesPageInfoProvider>
                  </FileQueryProvider>
                </CurrentRepositoryProvider>
              )}
            </Dialog.Subtitle>
          </Dialog.Header>
        )
      }}
      renderFooter={() => (
        <Dialog.Footer>
          <div className="d-flex flex-items-center">
            {fileCountExceeded ? (
              <FormControl.Validation variant="error">
                A maximum of {MAXIMUM_FILE_COUNT} files can be added.
              </FormControl.Validation>
            ) : savingError ? (
              <FormControl.Validation variant="error">{savingError}</FormControl.Validation>
            ) : null}
          </div>
          <div className="d-flex flex-row flex-justify-end gap-2">
            <Button onClick={onCancel}>Cancel</Button>
            <Button
              {...testIdProps('save-resource-button')}
              variant="primary"
              onClick={handleSave}
              count={isSaving ? undefined : selectedFileCount || undefined}
              loading={isSaving}
            >
              Add
            </Button>
          </div>
        </Dialog.Footer>
      )}
    >
      <div className="d-flex flex-column">
        {fetchError && <span>{fetchError}</span>}

        {!currentRepo && (
          <ReposSelector
            repositoryLoader={queryForRepos}
            selectionVariant="single"
            selectAllOption={false}
            currentSelection={undefined}
            onSelect={(repo: DropdownRepository | undefined) => {
              if (!repo) return
              setLocalFormData([])
              fetchRepo(repo.id)
            }}
            buttonText={localFormData[0]?.nwo || 'Select repository'}
          />
        )}
        {currentRepo && (
          <CurrentRepositoryProvider repository={currentRepo as unknown as Repository}>
            <FileQueryProvider>
              <FilesPageInfoProvider
                refInfo={{
                  name: currentRepo.refInfo.name,
                  canEdit: true,
                  listCacheKey: 'anything',
                  currentOid: currentRepo.commitOID,
                }}
                path="test"
                action="tree"
                copilotAccessAllowed
              >
                <FilePickerForm
                  expandedPath={expandedPath}
                  currentRepo={currentRepo}
                  localFormData={localFormData}
                  setLocalFormData={setLocalFormData}
                  onFileCountChange={setSelectedFileCount}
                  fetchError={fetchError}
                  processingTime={processingTime}
                />
              </FilesPageInfoProvider>
            </FileQueryProvider>
          </CurrentRepositoryProvider>
        )}
      </div>
    </Dialog>
  )
}
