import {Button} from '@primer/react'
import {XIcon} from '@primer/octicons-react'
import {marketplaceActionPath} from '@github-ui/paths'
import {useCSRFToken} from '@github-ui/use-csrf-token'
import type {ActionListing} from '@github-ui/marketplace-common'

interface DelistButtonProps {
  action: ActionListing
  delistActionData: {
    hydroAttrs: {[key: string]: string}
    repoAdminableByViewer: boolean
  }
}

export function DelistButton(props: DelistButtonProps) {
  const {action, delistActionData} = props
  const {hydroAttrs, repoAdminableByViewer} = delistActionData

  const authToken = useCSRFToken(marketplaceActionPath({slug: action.slug ?? ''}), 'delete')

  const hydroDataAttributes = Object.keys(hydroAttrs).reduce(
    (acc, key) => {
      acc[`data-${key}`] = hydroAttrs[key]
      return acc
    },
    {} as {[key: string]: unknown},
  )

  const delistDataAttrs = {
    'data-confirm':
      'Are you sure you want to delist this Action from the Marketplace? Note: This Action will still be installable as long as the repository is public.',
    'data-disable-with': 'Delisting...',
  }

  const combinedDataAttributes = {
    ...hydroDataAttributes,
    ...delistDataAttrs,
  }

  return (
    <>
      {repoAdminableByViewer && action.slug && (
        <form
          data-turbo="false"
          action={marketplaceActionPath({slug: action.slug})}
          method="post"
          data-testid="delist-form"
        >
          <input type="hidden" name="_method" value="delete" autoComplete="off" data-testid="hidden-delete" />
          <Button {...combinedDataAttributes} type="submit" data-testid="delist-button">
            <XIcon size={16} className={'mr-1'} />
            Delist
          </Button>
          {
            // eslint-disable-next-line github/authenticity-token
            <input type="hidden" name="authenticity_token" value={authToken} data-testid="hidden-authenticity-token" />
          }
        </form>
      )}
    </>
  )
}
