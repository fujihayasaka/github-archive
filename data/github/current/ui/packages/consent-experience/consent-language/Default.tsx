import type {GeneralConsentLanguageProps} from './ConsentLanguage'

export default function Default({
  fieldName,
  labelClass,
  formControlClass,
  privacyStatementHref,
  children,
  exampleFields,
  listExampleFields = false,
}: GeneralConsentLanguageProps) {
  return (
    <div className={formControlClass}>
      <label htmlFor={fieldName} className={labelClass} data-testid="label">
        {children}

        <p>
          Yes please, I&apos;d like GitHub and affiliates to use my information for personalized communications,
          targeted advertising and campaign effectiveness.{' '}
          {listExampleFields
            ? `The information used includes, but is not limited to, ${new Intl.ListFormat().format(exampleFields)}.`
            : null}{' '}
          <span>
            See the{' '}
            <a href={privacyStatementHref} className="text-underline">
              GitHub Privacy Statement
            </a>{' '}
            for more details.
          </span>
        </p>
      </label>
    </div>
  )
}
