import type {GeneralConsentLanguageProps} from './ConsentLanguage'

export default function Canada({
  fieldName,
  hasPhone = false,
  labelClass,
  formControlClass,
  privacyStatementHref,
  emailSubscriptionSettingsLinkHref,
  children,
}: GeneralConsentLanguageProps) {
  return (
    <div className={formControlClass}>
      <label htmlFor={fieldName} className={labelClass} data-testid="label">
        {children}

        <p>
          Yes, please, I&apos;d like to hear from GitHub and its family of companies via email{' '}
          {hasPhone ? 'and phone' : null} for personalized communications, targeted advertising, and campaign
          effectiveness. To withdraw consent or manage your contact preferences, visit the{' '}
          <a href={emailSubscriptionSettingsLinkHref} className="text-underline">
            Promotional Communications Manager
          </a>
          .{' '}
          <a href={privacyStatementHref} className="text-underline">
            GitHub Privacy Statement
          </a>
          .
        </p>
      </label>
    </div>
  )
}
