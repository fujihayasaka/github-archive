import {useCallback, useRef} from 'react'
import {ConfirmationDialog} from '@primer/react'
import {marketplaceActionPath} from '@github-ui/paths'
import {useCSRFToken} from '@github-ui/use-csrf-token'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {ActionListing} from '@github-ui/marketplace-common'

interface DelistFormProps {
  action: ActionListing
  repoAdminableByViewer: boolean
  isDialogOpen: boolean
  onDialogClose: () => void
}

export function DelistForm(props: DelistFormProps) {
  const {action, repoAdminableByViewer, isDialogOpen, onDialogClose} = props

  const authToken = useCSRFToken(marketplaceActionPath({slug: action.slug ?? ''}), 'delete')

  const formRef = useRef<HTMLFormElement>(null)

  const onDialogConfirm = useCallback(() => {
    if (formRef.current) {
      sendEvent('marketplace.action.delist', {
        repository_action_id: action.globalRelayId,
        source_url: `${window.location}`,
        location: 'actions#show',
      })
      formRef.current.submit()
    }
  }, [action.globalRelayId])

  return (
    repoAdminableByViewer &&
    action.slug && (
      <form
        ref={formRef}
        data-turbo="false"
        action={marketplaceActionPath({slug: action.slug})}
        method="post"
        data-testid="delist-form"
        className="d-none"
      >
        <input type="hidden" name="_method" value="delete" autoComplete="off" data-testid="hidden-delete" />
        {
          // eslint-disable-next-line github/authenticity-token
          <input type="hidden" name="authenticity_token" value={authToken} data-testid="hidden-authenticity-token" />
        }
        {isDialogOpen && (
          <ConfirmationDialog
            title="Delist action?"
            onClose={gesture => (gesture === 'confirm' ? onDialogConfirm() : onDialogClose())}
            confirmButtonContent="Delist action"
            confirmButtonType="danger"
          >
            Are you sure you want to delist this action from the Marketplace? Note: It will still be installable as long
            as the repository is public.
          </ConfirmationDialog>
        )}
      </form>
    )
  )
}
