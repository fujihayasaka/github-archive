import {Box, TextInput} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
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
      position={{narrow: 'fullscreen', regular: 'center'}}
      width="xlarge"
      onClose={onClose}
      renderHeader={({dialogLabelId}) => (
        <Dialog.Header
          sx={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', boxShadow: 'none', px: 3}}
        >
          <Dialog.Title id={dialogLabelId} {...testIdProps('share-preset-dialog')}>
            Share preset
          </Dialog.Title>
          <Dialog.CloseButton onClose={onClose} />
        </Dialog.Header>
      )}
      renderBody={({children}) => <Dialog.Body sx={{pt: 0}}>{children}</Dialog.Body>}
    >
      <div className="d-inline-flex flex-justify-between width-full mb-2">
        <span>Anyone with the URL will be able to view and use this preset, but not edit.</span>
      </div>

      <Box sx={{display: 'flex', height: '32px', gap: '8px'}}>
        <TextInput
          readOnly
          className="form-control input-sm color-bg-subtle"
          sx={{flex: 1}}
          data-autoselect
          value={shareableUrl}
          aria-label={shareableUrl}
        />
        <CopyToClipboardButton
          className="color-bg-subtle"
          iconButtonVariant="default"
          textToCopy={shareableUrl}
          ariaLabel="Copy url to clipboard"
          tooltipProps={{direction: 'nw'}}
        />
      </Box>
    </Dialog>
  )
}
