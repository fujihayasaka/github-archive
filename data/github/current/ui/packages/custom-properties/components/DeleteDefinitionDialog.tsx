import type {CheckPropertyUsagesResponse, PropertyDefinition} from '@github-ui/custom-properties-types'
import sudo from '@github-ui/sudo'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {DialogButtonProps} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {type RefObject, useEffect, useState} from 'react'

import {useSetBanner} from '../contexts/BannerContext'
import {useCheckUsagePath} from '../hooks/use-check-usage-path'
import {useDeletePropertyPath, useListPropertiesPath} from '../hooks/use-properties-paths'
import {DefinitionUsageBanner, ServerErrorFormBanner} from './Banners'
import styles from './DeleteDefinitionDialog.module.css'

interface Props {
  definition: PropertyDefinition
  returnFocusRef?: RefObject<HTMLElement>
  onCancel(): void
  onDismiss(): void
}
export function DeleteDefinitionDialog({definition, onDismiss, onCancel, returnFocusRef}: Props) {
  const setBanner = useSetBanner()
  const navigate = useNavigate()
  const [deleting, setDeleting] = useState(false)
  const [serverErrorMessage, setServerErrorMessage] = useState('')
  const [usages, setUsages] = useState<CheckPropertyUsagesResponse | undefined>()

  const deletePath = useDeletePropertyPath(definition.propertyName)
  const listPropertiesPath = useListPropertiesPath()

  const usagesDataRequested = usages !== undefined

  async function deleteDefinition() {
    if (deleting) return

    setDeleting(true)
    setServerErrorMessage('')

    if (!(await sudo())) {
      setServerErrorMessage('Unauthorized')
      setDeleting(false)
      return
    }

    const result = await verifiedFetchJSON(deletePath, {method: 'DELETE'})
    if (result.ok) {
      setBanner('definition.deleted.success')
      navigate(listPropertiesPath)
    } else {
      setServerErrorMessage('Something went wrong')
      setDeleting(false)
    }
  }

  const checkUsagePath = useCheckUsagePath(definition.propertyName)

  useEffect(() => {
    async function checkUsages() {
      const result = await verifiedFetchJSON(checkUsagePath)
      if (result.ok) {
        setUsages(await result.json())
      }
    }

    checkUsages()
  }, [definition.propertyName, checkUsagePath])

  if (deleting) {
    // A hack to escape the focus trap and focus sudo dialog.
    return null
  }

  return (
    <Dialog
      width="small"
      data-testid="delete-definition-dialog"
      onClose={onDismiss}
      title="Delete property"
      returnFocusRef={returnFocusRef}
      renderBody={() => (
        <>
          {serverErrorMessage && (
            <div aria-live="polite" className={styles.errorBannerContainer}>
              <ServerErrorFormBanner>{serverErrorMessage}</ServerErrorFormBanner>
            </div>
          )}

          <div>
            <div className={styles.usageCheckContainer}>
              {usages === undefined ? (
                <span>Checking usages...</span>
              ) : (
                <DefinitionUsageBanner name={definition.propertyName} repoCount={usages.repositoriesCount} />
              )}
            </div>
            <div className={styles.deletionWarningContainer}>
              <span>
                This will permanently delete this property. <strong>This cannot be undone.</strong>
              </span>
            </div>
          </div>
        </>
      )}
      footerButtons={[
        {
          onClick: onCancel,
          content: 'Cancel',
        },
        ...(usagesDataRequested
          ? [
              {
                buttonType: 'danger',
                onClick: deleteDefinition,
                content: deleting ? 'Deleting...' : 'Delete',
                'aria-disabled': deleting,
              } as DialogButtonProps,
            ]
          : []),
      ]}
    />
  )
}
