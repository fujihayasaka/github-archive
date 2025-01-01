import {useCallback, useEffect, useMemo, useState} from 'react'
import {AlertIcon, PlusIcon} from '@primer/octicons-react'
import {Button, Dialog, Spinner, TreeView} from '@primer/react'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {allowOrgModelsPayload, restrictOrgModelsPayload} from '../hooks/use-update-organization-access-policy'
import type {Model, Publisher} from '../types'
import {PublisherSelectionItem} from './PublisherSelectionItem'
import {useSelection} from '../contexts/SelectionContext'
import {usePublishers} from '../contexts/PublishersContext'
import {setDifference} from '../utils/set-utils'

export function AddRuleDialog({models, publishers}: {models: Model[]; publishers: Publisher[]}) {
  const [isOpen, setIsOpen] = useState(false)
  const {
    allowedModelKeys,
    didUpdateError,
    isAllowlist,
    isUpdatePending,
    pendingUpdateType,
    updateOrganizationAccessPolicy,
  } = useOrganizationAccessPolicy()
  const {fullySelectedPublisherIds, partiallySelectedPublisherIds, selectedModelKeys} = useSelection()
  const {allowedPublisherIds, blockedPublisherIds} = usePublishers()
  const blockedModelKeys = useMemo(
    () => setDifference(new Set(models.map(model => model.key)), allowedModelKeys),
    [allowedModelKeys, models],
  )

  useEffect(() => {
    if (!isUpdatePending && pendingUpdateType === 'rules') setIsOpen(false)
  }, [isUpdatePending, pendingUpdateType])

  const submitButtonLeadingVisual = useCallback(() => {
    if (pendingUpdateType === 'rules') {
      if (didUpdateError) return <AlertIcon />
      if (isUpdatePending) return <Spinner size="small" />
    }
    return null
  }, [didUpdateError, isUpdatePending, pendingUpdateType])

  const saveSelections = () => {
    if (isUpdatePending) return

    let newModelKeysToBlock = new Set<string>()
    let newModelKeysToAllow = new Set<string>()
    let newPublisherIdsToBlock = new Set<number>()
    let newPublisherIdsToAllow = new Set<number>()

    if (isAllowlist) {
      newPublisherIdsToBlock = setDifference(allowedPublisherIds, partiallySelectedPublisherIds)
      newPublisherIdsToAllow = setDifference(fullySelectedPublisherIds, allowedPublisherIds)
      newModelKeysToBlock = setDifference(allowedModelKeys, selectedModelKeys)
      newModelKeysToAllow = setDifference(selectedModelKeys, allowedModelKeys)
    } else {
      newPublisherIdsToBlock = setDifference(fullySelectedPublisherIds, blockedPublisherIds)
      newPublisherIdsToAllow = setDifference(blockedPublisherIds, partiallySelectedPublisherIds)
      newModelKeysToBlock = setDifference(selectedModelKeys, blockedModelKeys)
      newModelKeysToAllow = setDifference(blockedModelKeys, selectedModelKeys)
    }

    if (newModelKeysToBlock.size > 0 || newPublisherIdsToBlock.size > 0) {
      updateOrganizationAccessPolicy(
        restrictOrgModelsPayload({modelKeys: newModelKeysToBlock, publisherIds: newPublisherIdsToBlock}),
      )
    }

    if (newModelKeysToAllow.size > 0 || newPublisherIdsToAllow.size > 0) {
      updateOrganizationAccessPolicy(
        allowOrgModelsPayload({modelKeys: newModelKeysToAllow, publisherIds: newPublisherIdsToAllow}),
      )
    }
  }

  if (publishers.length < 1 && models.length < 1) return null

  return (
    <>
      <Button leadingVisual={<PlusIcon size="small" />} onClick={() => setIsOpen(true)} disabled={isUpdatePending}>
        Add models or publishers
      </Button>
      {isOpen && (
        <Dialog
          footerButtons={[
            {
              buttonType: 'primary',
              content: isAllowlist ? 'Update enabled list' : 'Update disabled list',
              disabled: isUpdatePending,
              onClick: saveSelections,
              leadingVisual: submitButtonLeadingVisual,
            },
          ]}
          width="large"
          onClose={() => setIsOpen(false)}
          title={`Select models and publishers to ${isAllowlist ? 'allow' : 'block'}`}
        >
          <p>
            Select models or publishers to <span>{isAllowlist ? 'allow' : 'prevent'}</span> members of your organization{' '}
            <span>{isAllowlist ? 'to use' : 'from using'}</span> them.
          </p>
          <form
            onSubmit={evt => {
              evt.preventDefault()
              saveSelections()
            }}
          >
            <TreeView aria-label="Select models and publishers">
              {publishers.map(publisher => (
                <PublisherSelectionItem
                  key={`publisher-${isAllowlist ? 'allow' : 'block'}-${publisher.id}`}
                  publisher={publisher}
                  models={models}
                />
              ))}
            </TreeView>
          </form>
        </Dialog>
      )}
    </>
  )
}
