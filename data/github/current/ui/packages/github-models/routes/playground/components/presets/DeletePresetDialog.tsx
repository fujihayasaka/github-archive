import {testIdProps} from '@github-ui/test-id-props'
import {ConfirmationDialog} from '@primer/react'

import type {Preset} from '../../../../types'
import {Banner} from '@primer/react/experimental'
import {useEffect, useRef, useState} from 'react'
import {deletePreset} from '../../../../utils/presets'

interface DeletePresetDialogProps {
  onClose: () => void
  onSuccess: () => void
  selectedPreset: Preset
}

export function DeletePresetDialog({onClose, onSuccess, selectedPreset}: DeletePresetDialogProps) {
  const [errors, setErrors] = useState<string | null>(null)

  const handleDelete = async () => {
    const {urlIdentifier, name} = selectedPreset

    try {
      const res = await deletePreset({urlIdentifier})
      if (res.ok) onSuccess()
      onClose()
    } catch {
      setErrors(`Failed to delete ${name} preset. Try again later.`)
    }
  }

  const handleClose = (gesture: 'confirm' | 'cancel' | 'close-button' | 'escape') => {
    if (gesture === 'confirm') {
      handleDelete()
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
          Delete prompt
        </div>
      }
      confirmButtonContent="Delete"
      confirmButtonType="danger"
    >
      {errors && (
        <Banner variant="critical" title="Something went wrong" description={errors} className="mb-2" ref={bannerRef} />
      )}
      Are you sure you want to delete this prompt?
    </ConfirmationDialog>
  )
}
