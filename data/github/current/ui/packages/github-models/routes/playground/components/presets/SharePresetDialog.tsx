import {TextInput, Dialog} from '@primer/react'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {testIdProps} from '@github-ui/test-id-props'

export interface SharePresetDialogProps {
  onClose: () => void
  playgroundUrl: string
  urlIdentifier: string | undefined
}

export function SharePresetDialog({onClose, playgroundUrl, urlIdentifier = ''}: SharePresetDialogProps) {
  if (!ssrSafeWindow) return

  const shareableUrl = new URL(`${playgroundUrl}?preset=${urlIdentifier}`, ssrSafeWindow.location.origin).href

  return (
    <Dialog
      onClose={onClose}
      title={
        <div {...testIdProps('share-preset-dialog')} className="text-medium">
          Share prompt
        </div>
      }
    >
      <p>Anyone with the URL will be able to view and use this prompt, but not edit.</p>
      <div className="d-flex gap-2">
        <TextInput
          readOnly
          className="form-control input-sm color-bg-subtle flex-1"
          data-autoselect
          value={shareableUrl}
          aria-label={shareableUrl}
        />
        <CopyToClipboardButton
          className="color-bg-subtle"
          variant="default"
          textToCopy={shareableUrl}
          ariaLabel="Copy url to clipboard"
          tooltipProps={{direction: 'nw'}}
        />
      </div>
    </Dialog>
  )
}
