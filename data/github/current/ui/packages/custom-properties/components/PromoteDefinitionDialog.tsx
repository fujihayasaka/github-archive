import type {PropertyDefinition, SourceInfo} from '@github-ui/custom-properties-types'
import {customPropertyDetailsPath, enterprisePath, promoteBusinessOrgCustomPropertyPath} from '@github-ui/paths'
import sudo from '@github-ui/sudo'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Dialog} from '@primer/react/experimental'
import {type RefObject, useState} from 'react'

import {useSetBanner} from '../contexts/BannerContext'
import {ServerErrorFormBanner} from './Banners'
import styles from './PromoteDefinitionDialog.module.css'

interface Props {
  business: SourceInfo
  definition: PropertyDefinition
  returnFocusRef?: RefObject<HTMLElement>
  onCancel(): void
  onDismiss(): void
}
export function PromoteDefinitionDialog({definition, business, onDismiss, onCancel, returnFocusRef}: Props) {
  const {propertyName, source} = definition

  const setBanner = useSetBanner()
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
      setBanner('definition.promotion.success')

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

  if (promoting) {
    // A hack to escape the focus trap and focus sudo dialog.
    return null
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
              <div className={styles.errorMessageContainer}>
                <ServerErrorFormBanner>{serverErrorMessage}</ServerErrorFormBanner>
              </div>
            )}
          </div>

          <div className={styles.promotionExplanationContainer}>
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
          </div>
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
