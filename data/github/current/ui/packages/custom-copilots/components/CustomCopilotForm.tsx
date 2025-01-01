import {Button, Truncate, FormControl, TextInput, PageLayout, Textarea, IconButton, VisuallyHidden} from '@primer/react'
import {DataTable, Banner} from '@primer/react/experimental'
import {RepoIcon, PencilIcon, TrashIcon, PlusCircleIcon, ArrowLeftIcon, FileIcon} from '@primer/octicons-react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useState, useMemo} from 'react'
import {testIdProps} from '@github-ui/test-id-props'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import type {
  CustomCopilot,
  CustomCopilotGitHubFileResource,
  CustomCopilotRepositoryResource,
  CustomCopilotResource,
  GitHubFileFormData,
} from '../types'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CustomCopilot as CustomCopilotItem, CopilotChatOrg} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {MultiFilePicker} from './MultiFilePicker'
import {getCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'

export interface CustomCopilotFormProps {
  customCopilot?: CustomCopilot
  findFileWorkerPath: string
  ssoOrganizations?: CopilotChatOrg[]
  updateCustomCopilot?: (customCopilot: CustomCopilotItem) => void
  tmpInitialForm?: boolean
}

// Represents the resource on the resource form. All fields are optional since the default form inputs are empty.
interface RepositoryFormData {
  id: string
  repositoryId?: number
  nwo?: string
  filePathFilters?: string
  type: 'repository'
}

interface FreeTextFormData {
  id: string
  type: 'free_text'
  text?: string
  name?: string
}

type ResourceFormData = RepositoryFormData | GitHubFileFormData | FreeTextFormData

const FormState = {
  initialForm: 'initialForm',
  editResourceForm: 'editResourceForm',
  newResourceForm: 'newResourceForm',
} as const

type FormState = (typeof FormState)[keyof typeof FormState]

export function CustomCopilotForm({
  customCopilot,
  findFileWorkerPath,
  updateCustomCopilot,
  ssoOrganizations,
  tmpInitialForm,
}: CustomCopilotFormProps) {
  const freeTextContentLimit = 20_000
  const generalInstructionsLimit = 2000
  const [name, setName] = useState(customCopilot?.name ?? '')
  const [description, setDescription] = useState(customCopilot?.description ?? '')
  const [generalInstructions, setGeneralInstructions] = useState(customCopilot?.generalInstructions ?? '')
  const [resourcesToSave, setResourcesToSave] = useState(customCopilot?.resources ?? [])
  const [formData, setFormData] = useState<ResourceFormData>({
    type: 'repository',
    id: 'new-repository-resource',
  })

  const ssoOrgNames = useMemo(() => {
    if (!ssoOrganizations) return []
    return ssoOrganizations.map(org => org.login)
  }, [ssoOrganizations])

  const [newResourceCount, setNewResourceCount] = useState(1)
  const [formState, setFormState] = useState<FormState>(FormState.initialForm)
  const [isSaving, setIsSaving] = useState(false)
  const [saveSuccessful, setSaveSuccessful] = useState(false)
  const showResourceForm = formState === FormState.editResourceForm || formState === FormState.newResourceForm
  // Error messages have a key that is the attribute name, and a string value that is the error message. For example:
  //
  //   {name: "can't be blank"}
  const [errorMessages, setErrorMessages] = useState<Record<string, string>>({})
  const [resourceFormErrorMessage, setResourceFormErrorMessage] = useState<string | null>(null)
  const visibleResources = resourcesToSave.filter(r => !r.markedForDestroy)

  const onGeneralInstructionsChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setGeneralInstructions(e.target.value)
  }

  const [showGitHubFileForm, setShowGitHubFileForm] = useState(false)
  const showFreeTextForm = showResourceForm && formData.type === 'free_text'

  return (
    <PageLayout containerWidth="medium" padding={tmpInitialForm ? 'none' : 'normal'}>
      <PageLayout.Content as="div">
        {formState === FormState.initialForm && (
          <form onSubmit={saveCustomCopilot} id={`custom-copilot-form-${customCopilot?.id}`} key={customCopilot?.id}>
            <div className={`d-flex flex-column gap-3 ${tmpInitialForm ? '' : 'p-3'}`}>
              {Object.keys(errorMessages).length > 0 && !tmpInitialForm && (
                <Banner
                  title="Failed to save this Copilot Space"
                  description={errorMessages.base}
                  variant="critical"
                  className="mb-2"
                  {...testIdProps('error-banner')}
                />
              )}

              {tmpInitialForm ? (
                <></>
              ) : (
                <>
                  <FormControl required>
                    <FormControl.Label required>Name</FormControl.Label>
                    <TextInput
                      block
                      value={name}
                      {...testIdProps('name-input')}
                      onChange={e => setName(e.target.value)}
                    />
                    {errorMessages.name && (
                      <FormControl.Validation variant="error">Name {errorMessages.name}</FormControl.Validation>
                    )}
                  </FormControl>

                  <FormControl>
                    <FormControl.Label>Description</FormControl.Label>
                    <TextInput
                      block
                      {...testIdProps('description-input')}
                      value={description}
                      onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                        setDescription(e.target.value)
                      }}
                    />
                  </FormControl>
                </>
              )}

              <FormControl>
                <FormControl.Label>General Instructions</FormControl.Label>
                <CharacterCount text={generalInstructions} promptCharLimit={generalInstructionsLimit} />
                <FormControl.Caption>
                  Describe the main responsibilities, limitations, and expertise areas of the Copilot. Include what
                  tasks it should handle and which ones to avoid.
                </FormControl.Caption>
                <Textarea
                  block
                  {...testIdProps('general-instructions-input')}
                  value={generalInstructions}
                  onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) => {
                    onGeneralInstructionsChange(e)
                  }}
                />
                {errorMessages.general_instructions && (
                  <FormControl.Validation variant="error">
                    General instructions {errorMessages.general_instructions}
                  </FormControl.Validation>
                )}
              </FormControl>

              <div>
                <h2 id="resources-title" className="f5">
                  Resources
                </h2>
                <p id="resources-subtitle" className="color-fg-muted f6">
                  Contexts, documents, or repositories that the Copilot uses to give accurate and relevant answers.
                </p>
                {ssoOrganizations && (
                  <SingleSignOnBanner protectedOrgs={ssoOrgNames} redirectURI={() => COPILOT_PATH} />
                )}
                {visibleResources.length > 0 && (
                  <div className="mt-2">
                    <DataTable
                      aria-labelledby="resources-title"
                      aria-describedby="resources-subtitle"
                      data={visibleResources}
                      columns={[
                        {
                          header: 'Name',
                          rowHeader: true,
                          id: 'id',
                          renderCell: row => {
                            return rowInfo(row)
                          },
                        },
                        {
                          id: 'actions',
                          header: () => <VisuallyHidden>Actions</VisuallyHidden>,
                          width: 'auto',
                          renderCell: row => {
                            return (
                              <>
                                {row.type !== 'github_file' && (
                                  <IconButton
                                    aria-label={'Edit this resource'}
                                    title={'Edit this resource'}
                                    icon={PencilIcon}
                                    variant="invisible"
                                    onClick={() => {
                                      setFormState(FormState.editResourceForm)
                                      setFormData({...row})
                                    }}
                                    {...testIdProps('edit-resource-button')}
                                  />
                                )}
                                <IconButton
                                  aria-label={'Delete this resource'}
                                  title={'Delete this resource'}
                                  icon={TrashIcon}
                                  variant="invisible"
                                  onClick={() => {
                                    setResourcesToSave(
                                      resourcesToSave.map(resource => {
                                        if (resource.id === row.id) {
                                          return {...resource, markedForDestroy: true}
                                        }
                                        return resource
                                      }),
                                    )
                                  }}
                                />
                              </>
                            )
                          },
                        },
                      ]}
                    />
                  </div>
                )}
              </div>
              <div className="gap-1 d-flex">
                <Button
                  size="small"
                  leadingVisual={PlusCircleIcon}
                  {...testIdProps('new-github-file-resource-button')}
                  onClick={() => {
                    setFormData({
                      id: 'new-github-file-resource',
                      type: 'github_file',
                      filePath: '',
                      repositoryId: 0,
                      nwo: '',
                    })
                    setShowGitHubFileForm(true)
                  }}
                >
                  Add file from a repository
                </Button>
                <Button
                  size="small"
                  leadingVisual={PlusCircleIcon}
                  {...testIdProps('new-free-text-resource-button')}
                  onClick={() => {
                    setFormData({id: 'new-free-text-resource', type: 'free_text'})
                    setFormState(FormState.newResourceForm)
                  }}
                >
                  Add text content
                </Button>
              </div>
              {saveSuccessful && tmpInitialForm && (
                <Banner title="Copilot Space saved successfully" variant="success" className="mb-2" />
              )}
              {Object.keys(errorMessages).length > 0 && tmpInitialForm && (
                <Banner
                  title="Failed to save this Copilot Space"
                  description={errorMessages.base}
                  variant="critical"
                  className="mb-2"
                  {...testIdProps('error-banner')}
                />
              )}
              <div className="d-flex flex-row flex-justify-end gap-2">
                <Button as="a" href="/copilot">
                  Cancel
                </Button>

                <Button
                  {...testIdProps('save-custom-copilot-button')}
                  type="submit"
                  variant="primary"
                  loading={isSaving}
                  loadingAnnouncement="Saving Copilot Space"
                >
                  Save
                </Button>
              </div>
            </div>
          </form>
        )}
        {showGitHubFileForm && (
          <MultiFilePicker
            formData={[formData] as GitHubFileFormData[]}
            onCancel={backToInitialForm}
            onSave={saveGitHubFileResource}
            findFileWorkerPath={findFileWorkerPath}
          />
        )}
        {showFreeTextForm && (
          <>
            <Button leadingVisual={ArrowLeftIcon} variant="invisible" onClick={() => backToInitialForm()}>
              Back
            </Button>

            <div className="d-flex flex-column gap-3 p-3">
              {resourceFormErrorMessage && <Banner variant="critical" title={resourceFormErrorMessage} />}

              <h1 className="f3">
                {formState === FormState.editResourceForm ? `Edit Text Content` : 'New Text Content'}
              </h1>

              <FormControl>
                <FormControl.Label>Name</FormControl.Label>
                <TextInput
                  {...testIdProps('free-text-name')}
                  block
                  value={formData.name || ''}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                    setFormData({...formData, name: e.target.value})
                  }}
                />
              </FormControl>

              <FormControl>
                <FormControl.Label>Content</FormControl.Label>
                <CharacterCount text={formData.text || ''} promptCharLimit={freeTextContentLimit} />
                <Textarea
                  block
                  {...testIdProps('free-text-textarea')}
                  value={formData.text}
                  onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) => {
                    setFormData({...formData, text: e.target.value})
                  }}
                />
              </FormControl>

              <div className="d-flex flex-row flex-justify-end gap-2">
                <Button onClick={() => backToInitialForm()}>Cancel</Button>
                <Button
                  {...testIdProps('save-resource-button')}
                  variant="primary"
                  onClick={() => saveFreeTextResource(formData)}
                >
                  Save
                </Button>
              </div>
            </div>
          </>
        )}
      </PageLayout.Content>
    </PageLayout>
  )

  /**
   * queues up the resources to be saved later when the user actually submits the form for the whole Copilot Space
   */
  function saveGitHubFileResource(data: GitHubFileFormData[]) {
    if (data.length === 0) {
      setResourceFormErrorMessage('Please select at least one file')
      return
    }

    const hasValidData = data.every(item => item.repositoryId && item.nwo && item.filePath)
    if (!hasValidData) {
      setResourceFormErrorMessage('Please select a repository and file paths')
      return
    }

    const filteredData = data.filter(item => {
      return !resourcesToSave.some(
        resource => resource.type === 'github_file' && resource.filePath === item.filePath && resource.nwo === item.nwo,
      )
    })

    setResourcesToSave([
      ...resourcesToSave,
      ...filteredData.map((item, index) => ({
        id: `newly-created-github-file-resource-${newResourceCount + index}`,
        repositoryId: item.repositoryId,
        nwo: item.nwo,
        markedForDestroy: false,
        filePath: item.filePath,
        type: 'github_file' as const,
      })),
    ])

    setNewResourceCount(newResourceCount + data.length)
    backToInitialForm()
  }

  /**
   * queues up the resource to be saved later when the user actually submits the form for the whole Copilot Space
   */
  function saveFreeTextResource(data: FreeTextFormData) {
    const text = data.text
    const fileName = data.name
    // Validate that text content and file name are present
    if (text && fileName && text.length < freeTextContentLimit) {
      if (formState === FormState.editResourceForm) {
        setResourcesToSave(
          resourcesToSave.map(resource => {
            if (resource.id === data.id && resource.type === 'free_text') {
              return {
                ...resource,
                markedForDestroy: false,
                text,
                name: fileName,
              }
            } else {
              return resource
            }
          }),
        )
      } else {
        setResourcesToSave([
          ...resourcesToSave,
          {
            id: `newly-created-free-text-resource-${newResourceCount}`, // for datatable to work we need an id. Since this is a new resource we don't have an id yet
            markedForDestroy: false,
            type: 'free_text',
            name: fileName,
            text,
          },
        ])
      }
      backToInitialForm()
    } else if (text && text.length >= freeTextContentLimit) {
      setResourceFormErrorMessage('Text must be shorter')
      return
    } else if (fileName === undefined || fileName === '') {
      setResourceFormErrorMessage('Name cannot be blank')
    } else {
      setResourceFormErrorMessage('Text cannot be blank')
      return
    }
  }

  function backToInitialForm() {
    setFormState(FormState.initialForm)
    setResourceFormErrorMessage(null)
    setFormData({type: 'free_text', id: 'new-free-text-resource'})
    setNewResourceCount(newResourceCount + 1)
    setShowGitHubFileForm(false)
  }

  async function saveCustomCopilot(event: React.FormEvent<HTMLFormElement>) {
    event?.preventDefault()
    // Prevents double saving
    if (isSaving) return
    setIsSaving(true)

    const method = customCopilot?.id ? 'PUT' : 'POST'
    const saveUrl = customCopilot?.id ? `/custom_copilots/${customCopilot.id}` : '/custom_copilots'
    const resp = await verifiedFetchJSON(saveUrl, {
      method,
      body: {
        custom_copilot: {
          name,
          description,
          general_instructions: generalInstructions,
          resources_attributes: resourcesToSave.map(resource => ({
            resource_type: resource.type,
            id: resource.databaseId,
            // The _destroy param is a special param used by Rails' accepts_nested_attributes_for. If set to true
            // the record will be deleted.
            _destroy: resource.markedForDestroy,
            metadata: resourceMetadataToRailsPayload(resource),
          })),
        },
      },
    })
    if (resp.ok) {
      const customCopilotData = await resp.json()
      const redirectUrl = getCopilotSpacePath(customCopilotData.id)

      if (tmpInitialForm) {
        setIsSaving(false)
        setSaveSuccessful(true)

        setErrorMessages({})
        updateCustomCopilot?.(customCopilotData)
        setResourcesToSave(customCopilotData.resources)
      } else {
        window.location.href = redirectUrl
      }
    } else {
      const unknownErrMsg = 'An unknown error occurred'
      const contentType = resp.headers?.get('content-type')

      if (contentType?.includes('application/json')) {
        setErrorMessages((await resp.json()).errorMessages || {base: unknownErrMsg})
      } else {
        setErrorMessages({base: unknownErrMsg})
      }
      // Only set isSaving(false) when it fails since we want to show an error message. On success we redirect so
      // we want to keep the loading state going until the index page is loaded
      setSaveSuccessful(false)
      setIsSaving(false)
      setSaveSuccessful(false)
    }
  }
}

function resourceMetadataToRailsPayload(resource: CustomCopilotResource) {
  switch (resource.type) {
    // We're not letting users make these on the front end now, but if we remove this
    // it'll break editing existing custom copilots
    case 'repository':
      return {
        repository_id: resource.repositoryId,
        file_path_filters: resource.filePathFilters?.split('\n').filter(path => path.trim() !== ''),
      }
    case 'github_file':
      return {
        repository_id: resource.repositoryId,
        file_path: resource.filePath,
      }
    case 'free_text':
      return {
        text: resource.text,
        name: resource.name,
      }
    default:
      throw new Error(`Unsupported resource`)
  }
}

function rowInfo(row: CustomCopilotResource) {
  switch (row.type) {
    // Temporarily here while we show existing repository resources, even though we're not letting
    // users create them for now.
    case 'repository':
      return <RepoRowInfo row={row} />
    case 'github_file':
      return <RepoRowInfo row={row} />
    case 'free_text':
      return (
        <Truncate title={row.name.slice(0, 100)} maxWidth={300} className="gap-1 d-flex">
          <FileIcon size={16} />
          {row.name}
        </Truncate>
      )
    default:
      throw new Error('Unsupported resource')
  }
}

function RepoRowInfo({row}: {row: CustomCopilotGitHubFileResource | CustomCopilotRepositoryResource}) {
  return (
    <span className="gap-2 d-flex flex-items-end">
      <RepoIcon size={16} />
      <span>{row.nwo}</span>
      <span className="fgColor-muted text-normal">{'filePath' in row ? row.filePath : row.filePathFilters}</span>
    </span>
  )
}

function CharacterCount({text, promptCharLimit}: {text: string; promptCharLimit: number}) {
  const tooLong = text.length > promptCharLimit
  const currentCount = (
    <>
      {text.length.toLocaleString()} / {promptCharLimit.toLocaleString()} characters
    </>
  )
  return (
    <>
      {tooLong ? (
        <FormControl.Validation variant="error">{currentCount}</FormControl.Validation>
      ) : (
        // This is a direct child, it just doesn't know that because it is a fragment within a function call
        // eslint-disable-next-line primer-react/direct-slot-children
        <FormControl.Caption>{currentCount}</FormControl.Caption>
      )}
    </>
  )
}
