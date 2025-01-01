import type {GeneralConsentLanguageProps} from './ConsentLanguage'

const copy = {
  preamble: 'I will receive personalized communications and targeted advertising from GitHub and affiliates. See the',
  privacyStatementText: 'GitHub Privacy Statement',
  postamble: 'for more details.',
}

export default function UnitedStates({labelClass, privacyStatementHref}: GeneralConsentLanguageProps) {
  return (
    <p className={labelClass}>
      {copy.preamble}{' '}
      <a href={privacyStatementHref} className="text-underline">
        {copy.privacyStatementText}
      </a>{' '}
      {copy.postamble}
    </p>
  )
}
