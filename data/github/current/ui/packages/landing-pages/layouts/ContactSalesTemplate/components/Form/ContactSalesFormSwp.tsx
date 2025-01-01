import {createContext, useState} from 'react'
import {Stack, Text} from '@primer/react-brand'
import {documentToReactComponents} from '@contentful/rich-text-react-renderer'
import {BLOCKS} from '@contentful/rich-text-types'

import {contactSalesPath, contactSalesThanksPath} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {ContentfulForm, type ContentfulFormProps} from '@github-ui/swp-core/components/contentful/ContentfulForm'
import {Flash} from '@github-ui/swp-core/components/Flash'
import {ConsentValue} from '@github-ui/swp-core/components/forms/ConsentExperience/types'
import type {Form} from '@github-ui/swp-core/schemas/contentful/contentTypes/form'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import {useParams} from '../../hooks/useParams'
import type {TemplateContactSalesForm} from '../../../../lib/types/contentful/contentTypes/templateContactSales'

function setRedirectUrl({queryParams, refId, baseUrl}: {queryParams: object; refId: string | null; baseUrl: string}) {
  const queryString = Object.entries(queryParams)
    .filter(param => param[1] !== null)
    .map(param => [param[0], encodeURIComponent(param[1] as string)].join('='))
    .join('&')
  const redirectUrl = `${baseUrl}?${queryString}`

  if (refId !== null) {
    return `${redirectUrl}&ref_id=${refId}`
  }

  return redirectUrl
}

type ContactSalesFormProps = {
  component: Form
  formRequirementMessage?: TemplateContactSalesForm['fields']['formRequirementMessage']
  redirectUrl?: string
}

export const ContactSalesFormContext = createContext<{contactSalesForm?: string}>({})

const defaultRedirectUrl = contactSalesThanksPath()

export function ContactSalesFormSwp({
  component,
  formRequirementMessage,
  redirectUrl = defaultRedirectUrl,
}: ContactSalesFormProps) {
  const queryParams = useParams()
  const [errorMessage, setErrorMessage] = useState<string | undefined>(undefined)

  const onSubmit: ContentfulFormProps['onSubmit'] = async values => {
    setErrorMessage(undefined)

    const {
      primaryConsent,
      marketing_email_opt_in,
      'octocaptcha-token': octocaptchaToken,
      directToSfdcCampaignId,
      cDLProgramName,
      sFDCLastCampaignStatus,
      source,
      ...submittedValues
    } = values

    const marketoValues = isFeatureEnabled('link_contact_sales_swp_marketo')
      ? {
          cdl_program_name: cDLProgramName,
          sfdc_last_campaign_status: sFDCLastCampaignStatus,
          source,
        }
      : {}

    // Marketing email opt-in for Contact Sales is looking for true or false values. The value for which consent
    // value to then forward to Marketing Forms API is made on the server side.

    const response = await verifiedFetchJSON(contactSalesPath(), {
      method: 'POST',
      body: {
        contact_sales_request: {
          ...submittedValues,
          ...marketoValues,
          ...queryParams,
          direct_to_sfdc_campaign_id: directToSfdcCampaignId,
          // Marketing email opt-in for Contact Sales is looking for true or false values. The value for which consent
          // value to then forward to Marketing Forms API is made on the server side.
          marketing_email_opt_in: marketing_email_opt_in === ConsentValue.EXPLICIT,
        },
        ['octocaptcha-token']: octocaptchaToken,
      },
    })

    if (response.ok) {
      const result = await response.json()
      const redirectUrlWithParams = setRedirectUrl({queryParams, refId: result.ref_id, baseUrl: redirectUrl})
      window.location.href = redirectUrlWithParams
    } else {
      setErrorMessage('We were unable to submit the form. Please try again.')
    }
  }

  return (
    <Stack direction="vertical" gap="normal">
      <Stack gap={8} direction="vertical" className="pb-3" padding="none">
        {formRequirementMessage ? (
          documentToReactComponents(formRequirementMessage, {
            renderNode: {
              [BLOCKS.PARAGRAPH]: (_, children) => (
                <Text as="p" size="100">
                  {children}
                </Text>
              ),
            },
          })
        ) : (
          <Text as="p" size="100">
            All fields marked with an asterisk (*) are required.
          </Text>
        )}
      </Stack>

      <ContentfulForm component={component} onSubmit={onSubmit} />

      <Flash hidden={errorMessage === undefined} variant="error">
        <Text as="p" weight="semibold" size="200">
          {errorMessage}
        </Text>
      </Flash>
    </Stack>
  )
}
