import type {PropertyDefinition, SourceInfo} from '@github-ui/custom-properties-types'
import {customPropertyDetailsPath, enterprisePath, promoteBusinessOrgCustomPropertyPath} from '@github-ui/paths'
import sudo from '@github-ui/sudo'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Box} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {type RefObject, useState} from 'react'

import {useSetFlash} from '../contexts/FlashContext'
import {ServerErrorFormBanner} from './Banners'

interface Props {
  business: SourceInfo
  definition: PropertyDefinition & Required<Pick<PropertyDefinition, 'source'>>
  returnFocusRef?: RefObject<HTMLElement>
  onCancel(): void
  onDismiss(): void
}
export function PromoteDefinitionDialog({definition, business, onDismiss, onCancel, returnFocusRef}: Props) {
  const {propertyName, source} = definition

  const setFlash = useSetFlash()
  const navigate = useNavigate()
  const [promoting, setPromoting] = useState(false)
  const [serverErrorMessage, setServerErrorMessage] = useState('')

  const promoteDefinition = async () => {
    if (promoting) return

    setPromoting(true)
    setServerErrorMessage('')

    if (!(await sudo())) {
      setServerErrorMessage('Unauthorized')
      setPromoting(false)
      return
    }

    const promotePath = promoteBusinessOrgCustomPropertyPath({org: source.slug, business: business.slug, propertyName})
    const result = await verifiedFetchJSON(promotePath, {method: 'POST'})
    if (result.ok) {
      setFlash('definition.promotion.success')

      navigate(customPropertyDetailsPath({pathPrefix: 'enterprises', sourceName: business.slug, propertyName}))
      onDismiss()
    } else {
      try {
        const {error} = await result.json()
        setServerErrorMessage(error)
      } catch {
        setServerErrorMessage('Something went wrong')
      }
      setPromoting(false)
    }
  }

  return (
    <Dialog
      width="large"
      data-testid="promote-definition-dialog"
      onClose={onDismiss}
      title="Promote to enterprise"
      returnFocusRef={returnFocusRef}
      renderBody={() => (
        <>
          <div aria-live="polite">
            {serverErrorMessage && (
              <Box sx={{px: 3, pt: 2}}>
                <ServerErrorFormBanner>{serverErrorMessage}</ServerErrorFormBanner>
              </Box>
            )}
          </div>

          <Box sx={{p: 3}}>
            <p>
              Promote this property to the enterprise level and make it available to every organization in your
              enterprise.
            </p>

            <p className="text-bold">What happens when you promote a property:</p>
            <ul className="ml-4">
              <li>
                Ownership of the property moves from the organization to the enterprise (
                <a href={enterprisePath(business)}>{business.name}</a>)
              </li>
              <li>All organizations in the enterprise will have access to the property</li>
              <li>All references to the property in the organization (i.e. ruleset targeting) will still work.</li>
            </ul>
          </Box>
        </>
      )}
      footerButtons={[
        {
          onClick: onCancel,
          content: 'Cancel',
        },
        {
          buttonType: 'primary',
          onClick: promoteDefinition,
          content: promoting ? 'Promoting…' : 'Promote',
          'aria-disabled': promoting,
        },
      ]}
    />
  )
}
