/* eslint eslint-comments/no-use: off */
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCopilotSpacePath, SLUG_ERROR_MESSAGE} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import type {
  CopilotSpacesConfigPayload,
  CustomCopilotFreeTextResource,
  CustomCopilotResource,
} from '@github-ui/custom-copilots/types'
import type {SpaceIconColor} from '@github-ui/custom-copilots/utils/space-icons'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {DotFillIcon, PaperclipIcon, PlusIcon, XIcon} from '@primer/octicons-react'
import {Button, FormControl, IconButton, ProgressBar, Stack, Textarea, TextInput} from '@primer/react'
import {Banner, Blankslate} from '@primer/react/experimental'
import {useId, useMemo, useRef, useState} from 'react'

import {AddAttachmentMenu} from './AddAttachmentMenu'
import {ColorPicker} from './ColorPicker'
import {useHideGlobalAppHeader} from './hooks/use-hide-global-app-header'
import {useUnsavedChangesWarning} from './hooks/use-unsaved-changes-warning'
import {useUpsertCopilotSpace} from './hooks/use-upsert-copilot-space'
import {ReferencesTable} from './ReferencesTable'
import {AssociatedRepositoryReferenceNotFoundBanner, ReferenceSizeExceededBanner} from './SpaceBanners'
import {SpacesAvatar} from './SpacesAvatar'
import styles from './SpacesForm.module.css'
import type {OwnerItem} from './SpacesOwnerDropdown'
import {SpacesOwnerDropdown} from './SpacesOwnerDropdown'

const DEFAULT_SPACE_ICON_COLOR = 'auburn' as SpaceIconColor

export function SpacesForm({copilotSpace, onCancel}: {copilotSpace?: CustomCopilot; onCancel: () => void}) {
  useHideGlobalAppHeader()

  const navigate = useNavigate()

  const {upsertCopilotSpace, isPending: isSaving} = useUpsertCopilotSpace(copilotSpace)

  const [spaceColor, setSpaceColor] = useState((copilotSpace?.iconColor ?? DEFAULT_SPACE_ICON_COLOR) as SpaceIconColor)
  const {
    copilotSpacesConfig: {maxGeneralInstructionsLength, maxDescriptionLength},
  } = useAppPayload<CopilotSpacesConfigPayload>()

  const [name, setName] = useState(copilotSpace?.name ?? '')
  const [description, setDescription] = useState(copilotSpace?.description ?? '')
  const [generalInstructions, setGeneralInstructions] = useState(copilotSpace?.generalInstructions ?? '')
  const [resourcesToSave, setResourcesToSave] = useState(copilotSpace?.resources ?? ([] as CustomCopilotResource[]))
  const [owner, setOwner] = useState<OwnerItem | null>(null)
  const isOrgSpace = owner?.type === 'Organization' || copilotSpace?.ownerIsOrg
  const filePickerOwner = isOrgSpace ? owner?.name || copilotSpace?.owner : undefined

  // Error messages have a key that is the attribute name, and a string value that is the error message. For example:
  //
  //   {name: "can't be blank"}
  //
  const [errorMessages, setErrorMessages] = useState<Record<string, string>>({})
  const visibleResources = resourcesToSave.filter(r => !r.markedForDestroy)
  const attachmentButtonRef = useRef<HTMLButtonElement>(null)
  const isEditing = !!copilotSpace
  const currentSpaceSizePercentage = useMemo(() => {
    return visibleResources.reduce((acc, resource) => acc + (resource.sizePercentage || 0), 0)
  }, [visibleResources])
  const formId = useId()
  const referenceSizeExceeded = currentSpaceSizePercentage > 100.0

  const initialSpaceValue = useMemo(() => {
    return {
      name: copilotSpace?.name.trim() || '',
      description: (copilotSpace?.description || '').trim(),
      generalInstructions: (copilotSpace?.generalInstructions || '').trim(),
      owner: copilotSpace?.owner || '',
      iconColor: copilotSpace?.iconColor || DEFAULT_SPACE_ICON_COLOR,
      resources: copilotSpace?.resources || [],
    }
  }, [copilotSpace])

  const isDirty = useMemo(() => {
    return (
      name.trim() !== initialSpaceValue.name ||
      description.trim() !== initialSpaceValue.description ||
      generalInstructions.trim() !== initialSpaceValue.generalInstructions ||
      spaceColor !== initialSpaceValue.iconColor ||
      resourcesToSave.some(r => {
        // destroy old database or add a new file (no databaseId)
        if (r.markedForDestroy || !r.databaseId) return true

        // if free text compare the name and content
        if (r.type === 'free_text') {
          const existingResource = initialSpaceValue.resources.find(
            x => x.databaseId === r.databaseId,
          ) as CustomCopilotFreeTextResource
          if (!existingResource) return true
          return r.text.trim() !== existingResource.text.trim() || r.name.trim() !== existingResource.name.trim()
        }
      })
    )
  }, [initialSpaceValue, name, description, generalInstructions, spaceColor, resourcesToSave])
  useUnsavedChangesWarning(isDirty)

  const saveSpace = async () => {
    if (isSaving) return

    try {
      const newSpace = await upsertCopilotSpace({
        name,
        description,
        generalInstructions,
        ownerId: owner?.id,
        ownerType: owner?.type,
        resources: resourcesToSave,
        iconColor: spaceColor,
        iconType: 'SpacesIcon',
      })

      setErrorMessages({})
      // navigate to the newly created space
      const path = getCopilotSpacePath(newSpace)
      return navigate(path)
    } catch (errors) {
      const errs = errors ?? {}
      setErrorMessages(errs as Record<string, string>)
    }
  }

  const handleSubmit = (e?: React.FormEvent<HTMLElement>) => {
    e?.preventDefault()
    void saveSpace()
  }

  function handleDeleteResource(resource: CustomCopilotResource) {
    if (resource.databaseId) {
      setResourcesToSave(prevResources =>
        prevResources.map(r => (resource.databaseId === r.databaseId ? {...r, markedForDestroy: true} : r)),
      )
    } else {
      // if the resource has just been added and not in the database
      // we should just filter it out instead
      setResourcesToSave(prevResources => prevResources.filter(r => r.id !== resource.id))
    }
  }

  function handleUpdateResource(resource: CustomCopilotResource) {
    const updatedResources = resourcesToSave.map(r => (r.id === resource.id ? resource : r))
    setResourcesToSave(updatedResources)
  }

  function clearErrors(fields: string[]) {
    const updatedErrorMessages = {...errorMessages}
    for (const field of fields) {
      if (updatedErrorMessages[field]) {
        delete updatedErrorMessages[field]
      }
    }
    setErrorMessages(updatedErrorMessages)
  }

  return (
    <>
      <div className={styles.header}>
        <div className={styles.headerTitleContainer}>
          <IconButton icon={XIcon} aria-label="Close" variant="invisible" onClick={onCancel} />
          <div className={styles.headerTitleDivider} aria-hidden="true" />
          <h1 className={styles.headerTitle} id="page-title">
            {isEditing ? 'Edit space' : 'New space'}
          </h1>
        </div>
        <Stack align="center" direction="horizontal" gap="condensed">
          {isDirty && copilotSpace && (
            <div className="fgColor-attention text-small mr-2">
              <DotFillIcon size={14} />
              <span> Unsaved changes</span>
            </div>
          )}
          <Button onClick={onCancel}>Cancel</Button>
          <Button type="submit" variant="primary" form={formId} loading={isSaving}>
            Save
          </Button>
        </Stack>
      </div>

      <div className={styles.page}>
        <form id={formId} className={styles.form} onSubmit={handleSubmit}>
          {errorMessages.base && (
            <Banner
              title="Failed to save this space"
              description={errorMessages.base}
              variant="critical"
              className="mb-2"
            />
          )}
          <FormControl>
            <FormControl.Label>Name</FormControl.Label>
            <TextInput
              autoFocus
              block
              name="name"
              value={name}
              onChange={e => {
                setName(e.target.value)
                clearErrors(['name', 'slug'])
              }}
            />
            {errorMessages.name ? (
              <FormControl.Validation variant="error">
                <span>Name {errorMessages.name}</span>
              </FormControl.Validation>
            ) : errorMessages.slug ? (
              <FormControl.Validation variant="error">
                <span>{SLUG_ERROR_MESSAGE}</span>
              </FormControl.Validation>
            ) : null}

            <FormControl.Caption>Memorable name that helps you find your space.</FormControl.Caption>
          </FormControl>

          <div className={styles.iconPreviewContainer}>
            <div className={styles.iconAvatarContainer}>
              <SpacesAvatar size={24} color={spaceColor} />
            </div>
            <div>
              <div className={styles.iconPreviewTitle}>Icon</div>
              <div className={styles.iconPreviewDescription}>Pick a color to make your space more recognizable.</div>
              <ColorPicker value={spaceColor} onChange={setSpaceColor} />
            </div>
          </div>

          {!isEditing && <SpacesOwnerDropdown onSelect={newOwner => setOwner(newOwner)} />}

          <FormControl>
            <FormControl.Label required={false} requiredIndicator>
              Description <span className={styles.optionalLabel}>(optional)</span>
            </FormControl.Label>
            <Textarea
              block
              name="description"
              value={description}
              rows={3}
              resize="vertical"
              className={styles.textAreaWrapper}
              onChange={e => {
                setDescription(e.target.value)
                clearErrors(['description'])
              }}
            />
            {errorMessages.description ? (
              <FormControl.Validation variant="error">
                <span>Description {errorMessages.description}</span>
              </FormControl.Validation>
            ) : (
              <CharacterCount text={description} promptCharLimit={maxDescriptionLength} />
            )}
            <FormControl.Caption>
              Displays beneath the title on your spaces overview page without impacting responses.
            </FormControl.Caption>
          </FormControl>

          <FormControl id="instructions">
            <FormControl.Label required={false} requiredIndicator>
              Instructions <span className={styles.optionalLabel}>(optional)</span>
            </FormControl.Label>
            <Textarea
              block
              name="instructions"
              value={generalInstructions}
              resize="vertical"
              className={styles.textAreaWrapper}
              onChange={e => {
                setGeneralInstructions(e.target.value)
                clearErrors(['general_instructions'])
              }}
            />
            {errorMessages['general_instructions'] ? (
              <FormControl.Validation variant="error">
                <span>Instructions {errorMessages['general_instructions']}</span>
              </FormControl.Validation>
            ) : (
              <CharacterCount text={generalInstructions} promptCharLimit={maxGeneralInstructionsLength} />
            )}
            <FormControl.Caption>Changes how Copilot responds on specific questions or tasks.</FormControl.Caption>
          </FormControl>

          <div id="attachments">
            <div className={styles.contextHeader}>
              <div className={styles.attachmentsHeading}>
                Attachments <span className={styles.optionalLabel}>(optional)</span>
              </div>
              <Stack direction="horizontal" align="center" gap="none">
                {currentSpaceSizePercentage > 0 && (
                  <>
                    <ProgressBar
                      inline
                      barSize="small"
                      progress={currentSpaceSizePercentage}
                      className={styles.referencesSizeProgressBar}
                      aria-hidden="true"
                    />
                    <span className="sr-only">
                      {`${Math.max(0, Math.round(100 - currentSpaceSizePercentage))}% remaining attachment capacity`}
                    </span>
                    <span className={styles.referencesSizeText}>
                      {currentSpaceSizePercentage < 1 ? '<1' : Math.round(currentSpaceSizePercentage)}%
                    </span>
                  </>
                )}
                <AddAttachmentMenu
                  sizePercentage={currentSpaceSizePercentage}
                  findFileWorkerPath={''}
                  owner={filePickerOwner}
                  onResourcesAdded={newResources => {
                    setResourcesToSave(prevResources => {
                      // Create a Map from prevResources for efficient lookups and insertions
                      const resourceMap = new Map(prevResources.map(resource => [resource.id, resource]))
                      // Add or update resources from newResources
                      for (const newResource of newResources) {
                        // If the resource already exists, this will overwrite it. Otherwise, it will add a new entry.
                        resourceMap.set(newResource.id, newResource)
                      }
                      // Convert the Map back to an array
                      return Array.from(resourceMap.values())
                    })
                  }}
                  resourcesToSave={resourcesToSave}
                >
                  <Button size="small" leadingVisual={PlusIcon} ref={attachmentButtonRef} aria-label="Add attachment">
                    Add
                  </Button>
                </AddAttachmentMenu>
              </Stack>
            </div>

            {referenceSizeExceeded && <ReferenceSizeExceededBanner />}
            {errorMessages['resources.repository'] && <AssociatedRepositoryReferenceNotFoundBanner />}

            {visibleResources.length === 0 ? (
              <div>
                <Blankslate border spacious>
                  <Blankslate.Visual>
                    <PaperclipIcon size={24} />
                  </Blankslate.Visual>
                  <Blankslate.Description>
                    Add text, code files, or GitHub data to set a permanent context
                  </Blankslate.Description>
                </Blankslate>
              </div>
            ) : (
              <ReferencesTable
                sizePercentage={currentSpaceSizePercentage}
                resources={visibleResources}
                onDeleteResource={handleDeleteResource}
                onUpdateResource={handleUpdateResource}
              />
            )}
          </div>
        </form>
      </div>
    </>
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
