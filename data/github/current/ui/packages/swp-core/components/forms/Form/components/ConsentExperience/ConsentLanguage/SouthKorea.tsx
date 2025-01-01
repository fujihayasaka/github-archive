import {useContext, useEffect, useState} from 'react'
import {Checkbox, FormControl, InlineLink, Stack, Text, UnorderedList} from '@primer/react-brand'
import {DotFillIcon} from '@primer/octicons-react'
import {z} from 'zod/v4'

import {FormContext} from '../../../FormContext'
import type {GeneralConsentLanguageProps} from './types'
import {getAnalyticsEvent} from '../../../../../../lib/utils/analytics'

const copy = {
  privacyStatementText: 'GitHub Privacy Statement',
}

export default function SouthKorea({
  fieldName,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  exampleFields = [],
  privacyStatementHref,
  children,
  onValidationChange,
}: GeneralConsentLanguageProps) {
  const fields = exampleFields.join(', ')
  const formContext = useContext(FormContext)
  const {
    ref,
    onChange: primaryConsentOnChange,
    id,
    ...primaryConsentProps
  } = formContext?.register('primaryConsent', {
    label: 'Required Consent',
    required: true,
    validations: [{message: 'You need to accept the required checkboxes to continue.', schema: z.literal(true)}],
  }) ?? {}

  /**
   * Since South Korea requires explicit acceptance of the primary consent, we use false as the default value.
   */
  const [isPrimaryConsentAccepted, setPrimaryConsentAcceptance] = useState(false)

  const onPrimaryConsentChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    primaryConsentOnChange?.(event)
    setPrimaryConsentAcceptance(event.target.checked)
  }

  useEffect(() => {
    return function cleanup() {
      formContext?.unregister?.('primaryConsent')
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  /**
   * We call `onValidationChange` with `false` as the component mounts, and
   * then again whenever the primary consent changes.
   */
  useEffect(() => {
    if (onValidationChange) {
      onValidationChange(isPrimaryConsentAccepted)
    }
  }, [onValidationChange, isPrimaryConsentAccepted])

  return (
    <Stack direction="vertical" padding="none" gap="condensed">
      <FormControl>
        <FormControl.Label htmlFor="south-korea-primary-consent">
          <Text>I agree to the collection and use of my personal information (required)*:</Text>

          <UnorderedList>
            <UnorderedList.Item leadingVisual={DotFillIcon} leadingVisualFill="default">
              <Text>
                Items of Personal Information to be Collected: {fields}, and any other fields visible on this form.
              </Text>
            </UnorderedList.Item>
            <UnorderedList.Item leadingVisual={DotFillIcon} leadingVisualFill="default">
              <Text>
                Purpose of Collection and Use: GitHub will use the data for the purpose described on this form.
              </Text>
            </UnorderedList.Item>
            <UnorderedList.Item leadingVisual={DotFillIcon} leadingVisualFill="default">
              <Text>
                Retention/Use Period of Personal Information:{' '}
                <Text as="span" size="300" weight="bold">
                  As long as needed to provide the service(s) you are requesting
                </Text>
              </Text>
            </UnorderedList.Item>
          </UnorderedList>
        </FormControl.Label>

        <Checkbox
          type="checkbox"
          id="south-korea-primary-consent"
          checked={isPrimaryConsentAccepted}
          onChange={onPrimaryConsentChange}
          required
          ref={ref}
          aria-describedby={id && `${id}-validation`}
          {...getAnalyticsEvent({
            action: 'primary_consent_south_korea',
            tag: 'checkbox',
            context: 'form_submit',
            location: 'form',
          })}
          {...primaryConsentProps}
        />
      </FormControl>

      <FormControl>
        <FormControl.Label htmlFor={fieldName} data-testid="label">
          <Text>
            I agree to receiving marketing information and use of my personal information for marketing purposes
            (optional):
          </Text>
          <UnorderedList>
            <UnorderedList.Item leadingVisual={DotFillIcon} leadingVisualFill="default">
              <Text>
                <Text as="span" size="300" weight="bold">
                  Consent to Receive Marketing:
                </Text>{' '}
                The information collected may be used for GitHub for personalized communications, targeted advertising
                and campaign effectiveness.
              </Text>
            </UnorderedList.Item>
            <UnorderedList.Item leadingVisual={DotFillIcon} leadingVisualFill="default">
              <Text>
                Items of Personal Information to be Collected: {fields}, and any other fields visible on this form.
              </Text>
            </UnorderedList.Item>
            <UnorderedList.Item leadingVisual={DotFillIcon} leadingVisualFill="default">
              <Text>
                Purpose of Collection and Use:{' '}
                <Text as="span" size="300" weight="bold">
                  To contact you for marketing purposes.
                </Text>
              </Text>
            </UnorderedList.Item>
            <UnorderedList.Item leadingVisual={DotFillIcon} leadingVisualFill="default">
              <Text>
                Retention/Use Period of Personal Information:{' '}
                <Text as="span" size="300" weight="bold">
                  As long as needed to provide the service(s) you are requesting.
                </Text>
              </Text>
            </UnorderedList.Item>
          </UnorderedList>
        </FormControl.Label>

        {children}
      </FormControl>

      <Text variant="muted">
        You have the right to refuse the collection and use of your personal information, use of personal information
        for marketing purposes, and receiving marketing information as set forth above. However, if you refuse, you may
        not be able to receive the benefits described under Purpose of Collection & Use.{' '}
        <InlineLink
          {...getAnalyticsEvent({
            action: copy.privacyStatementText,
            tag: 'hyperlink',
            context: 'consent_language_south_korea',
            location: 'form',
          })}
          href={privacyStatementHref}
        >
          {copy.privacyStatementText}
        </InlineLink>
        .
      </Text>
    </Stack>
  )
}
