import {Button, FormControl, TextInput} from '@primer/react'
import {ArrowLeftIcon} from '@primer/octicons-react'
import {testIdProps} from '@github-ui/test-id-props'
import {ReposSelector} from '@github-ui/repos-selector'
import {CurrentRepositoryProvider, type Repository} from '@github-ui/current-repository'
import FileResultsList from './files-search/FileResultsList'
import {FilesPageInfoProvider} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {FileQueryProvider} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useState} from 'react'
import type {CopilotChatRepo, GitHubFileFormData} from '../types'

interface DropdownRepository {
  id: number
  name: string
  enabled: boolean
}

interface Props {
  formData: GitHubFileFormData
  onCancel: () => void
  onSave: (data: GitHubFileFormData[]) => void
  findFileWorkerPath: string
}

export function GitHubFileForm({formData, onCancel, onSave, findFileWorkerPath}: Props) {
  const [resourceFormErrorMessage, setResourceFormErrorMessage] = useState<string | null>(null)
  const [repoDetailsCache, setRepoDetailsCache] = useState<Record<number, CopilotChatRepo>>({})
  const [fetchError, setFetchError] = useState<string | null>(null)
  const [currentRepo, setCurrentRepo] = useState<CopilotChatRepo | null>(null)
  const [localFormData, setLocalFormData] = useState(formData)

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

  const handleSave = () => {
    const repositoryId = localFormData.repositoryId
    const nwo = localFormData.nwo
    if (repositoryId && nwo) {
      onSave([localFormData])
    } else {
      setResourceFormErrorMessage('You must select a repository')
    }
  }

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
    <>
      <Button leadingVisual={ArrowLeftIcon} variant="invisible" onClick={onCancel}>
        Back
      </Button>

      <div className="d-flex flex-column gap-3 p-3">
        {resourceFormErrorMessage && <span>{resourceFormErrorMessage}</span>}
        {fetchError && <span>{fetchError}</span>}

        <h1 className="f3">{'New GitHub File'}</h1>

        <div>
          <ReposSelector
            repositoryLoader={queryForRepos}
            selectionVariant="single"
            selectAllOption={false}
            currentSelection={undefined}
            onSelect={(repo: DropdownRepository | undefined) => {
              if (!repo) return
              setLocalFormData({
                ...localFormData,
                repositoryId: repo.id,
                nwo: repo.name,
              })
              fetchRepo(repo.id)
            }}
            buttonText={localFormData.nwo || 'Select repository'}
          />
        </div>

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
                <FormControl>
                  <FormControl.Label>File path</FormControl.Label>
                  <TextInput
                    block
                    value={localFormData.filePath || ''}
                    onChange={e => {
                      setLocalFormData({...localFormData, filePath: e.target.value})
                    }}
                    {...testIdProps('resource-file-path-input')}
                  />
                </FormControl>
                <FileResultsList
                  commitOid={currentRepo.commitOID}
                  findFileWorkerPath={findFileWorkerPath}
                  onItemSelected={path => {
                    setLocalFormData({...localFormData, filePath: path || ''})
                  }}
                  config={{
                    enableOverlay: true,
                    disableNavigation: true,
                    searchPlaceholder: 'Select a file',
                    actionText: 'Select a file',
                  }}
                  sx={{mr: 1, ml: 1}}
                />
              </FilesPageInfoProvider>
            </FileQueryProvider>
          </CurrentRepositoryProvider>
        )}

        <div className="d-flex flex-row flex-justify-end gap-2">
          <Button onClick={onCancel}>Cancel</Button>
          <Button {...testIdProps('save-resource-button')} variant="primary" onClick={handleSave}>
            Save
          </Button>
        </div>
      </div>
    </>
  )
}
