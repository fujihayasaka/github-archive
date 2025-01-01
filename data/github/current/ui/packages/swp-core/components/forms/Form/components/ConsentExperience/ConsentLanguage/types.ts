export interface GeneralConsentLanguageProps {
  fieldName: string
  privacyStatementHref: string
  emailSubscriptionSettingsLinkHref: string
  hasPhone?: boolean
  exampleFields?: string[]
  labelClass?: string
  formControlClass?: string
  noticeClass?: string
  children: React.ReactNode
  onValidationChange?: (isValid: boolean) => void
}
