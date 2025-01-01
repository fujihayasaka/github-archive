import {testIdProps} from '@github-ui/test-id-props'
import {ConfirmationDialog} from '@primer/react'

import type {Preset} from '../../../../types'
import {Banner} from '@primer/react/experimental'
import {useEffect, useRef} from 'react'
import styles from './DeletePresetDialog.module.css'

interface DeletePresetDialogProps {
  onClose: () => void
  onSubmit: (selectedPreset: Preset) => void
  selectedPreset: Preset
  errors?: string
}

export function DeletePresetDialog({onClose, onSubmit, selectedPreset, errors}: DeletePresetDialogProps) {
  const handleClose = (gesture: 'confirm' | 'cancel' | 'close-button' | 'escape') => {
    if (gesture === 'confirm') {
      onSubmit(selectedPreset)
    } else {
      onClose()
    }
  }
  const bannerRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (errors) {
      bannerRef.current?.focus()
    }
  }, [errors])

  return (
    <ConfirmationDialog
      onClose={handleClose}
      title={
        <div {...testIdProps('delete-preset-dialog')} className="text-medium">
          Delete preset
        </div>
      }
      confirmButtonContent="Delete"
      confirmButtonType="danger"
    >
      {errors && (
        <Banner
          variant="critical"
          title="Something went wrong"
          description={errors}
          className={styles.bannerDeletePresetDialog}
          ref={bannerRef}
        />
      )}
      Are you sure you want to delete this preset?
    </ConfirmationDialog>
  )
}
