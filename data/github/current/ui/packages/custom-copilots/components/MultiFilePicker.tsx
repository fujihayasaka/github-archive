import {Box, Button, FormControl, IconButton} from '@primer/react'
import {testIdProps} from '@github-ui/test-id-props'
import {ReposSelector} from '@github-ui/repos-selector'
import {XIcon} from '@primer/octicons-react'
import {CurrentRepositoryProvider, type Repository} from '@github-ui/current-repository'
import {FilesPageInfoProvider} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {FileQueryProvider} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useState, useEffect, useCallback} from 'react'
import type {CopilotChatRepo, GitHubFileFormData} from '../types'
import type {TreeItem} from '@github-ui/repos-file-tree-view'
import type {DirectoryItem} from '@github-ui/code-view-types'
import FileResultsList from './files-search/FileResultsList'
import {useTreeList} from '@github-ui/code-view-shared/hooks/use-tree-list'
import {convertFlatPathsToTreeItems} from '../utils/convert-tree-data'
import {Dialog} from '@primer/react/experimental'
import {FileTreePicker} from './file-tree-picker/FileTreePicker'
import {AllShortcutsEnabledProvider} from '@github-ui/code-view-shared/contexts/AllShortcutsEnabledContext'
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

const MAXIMUM_FILE_COUNT = 20

function FilePickerForm({
  currentRepo,
  setLocalFormData,
  fetchError,
  onFileCountChange,
  processingTime,
  expandedPath,
}: FilePickerFormProps) {
  const [selectedItems, setSelectedItems] = useState<Set<string>>(new Set())
  const [allDirectories, setAllDirectories] = useState<Set<string>>(new Set())

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
        }}
      >
        <div>
          <div className="react-tree-show-tree-items">
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
          </div>
        </div>
      </Box>
    </>
  )
}

function CloseButton({onClose}: {onClose: () => void}) {
  return <IconButton icon={XIcon} aria-label="Close add file dialog" onClick={onClose} variant="invisible" />
}

export function MultiFilePicker({formData, onCancel, onSave, findFileWorkerPath}: Props) {
  const [repoDetailsCache, setRepoDetailsCache] = useState<Record<number, CopilotChatRepo>>({})
  const [fetchError, setFetchError] = useState<string | null>(null)
  const [currentRepo, setCurrentRepo] = useState<CopilotChatRepo | null>(null)
  const [localFormData, setLocalFormData] = useState<GitHubFileFormData[]>(formData)
  const [processingTime] = useState(0)
  const [isSaving, setIsSaving] = useState(false)
  const [savingError, setSavingError] = useState<string | null>(null)

  const [expandedPath, setExpandedPath] = useState('')
  const [selectedFileCount, setSelectedFileCount] = useState(0)

  const fetchRepo = async (repoID: number): Promise<void> => {
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
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An unknown error occurred'
      setFetchError(errorMessage)
    }
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
    } catch (error) {
      let errorMessage = (error as Record<string, string>)['base'] ?? 'An unknown error occurred'

      if (errorMessage.startsWith('The size of the space exceeds the current limit')) {
        errorMessage = 'The size of the space exceeds the current limit'
      }

      setSavingError(errorMessage)
    } finally {
      setIsSaving(false)
    }
  }

  useEffect(() => {
    setSavingError(null)
  }, [localFormData])

  async function queryForRepos(query: string) {
    const response = await verifiedFetchJSON(`/_filter/repositories?q=${encodeURIComponent(query)}`)
    if (response.ok) {
      const repos = (await response.json()).repositories.map((repo: {id: number; nameWithOwner: string}) => {
        return {name: repo.nameWithOwner, enabled: true, id: repo.id}
      })
      return repos
    }
    return []
  }

  return (
    <Dialog
      onClose={onCancel}
      title="Add files"
      sx={{maxHeight: '500px'}}
      renderHeader={({onClose}) => {
        return (
          <Dialog.Header>
            <div className="d-flex flex-justify-between flex-items-center px-2">
              <Dialog.Title>Add files</Dialog.Title>
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
                            searchPlaceholder: 'Search for files or folders',
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
              count={selectedFileCount || undefined}
              loading={isSaving}
            >
              Add files
            </Button>
          </div>
        </Dialog.Footer>
      )}
    >
      <div className="d-flex flex-column">
        {fetchError && <span>{fetchError}</span>}

        {!currentRepo && (
          <div>
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
          </div>
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
