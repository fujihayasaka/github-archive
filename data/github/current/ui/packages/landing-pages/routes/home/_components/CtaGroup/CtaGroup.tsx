import {FormControl, TextInput, ThemeProvider, Button} from '@primer/react-brand'

import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import type {GenericCTAGroup} from '../../../../brand/lib/types/contentful'

import {CtaButtons} from './CtaButtons'

type Props = {
  contentfulContent: GenericCTAGroup[]
  location: string
}

export function CtaGroup(props: Props) {
  const {isLoggedIn = false, hasOrganization = false} = useRoutePayload<{
    isLoggedIn: boolean
    hasOrganization: boolean
  }>()

  const {contentfulContent, location} = props

  const defaultCtas = contentfulContent.find(ctaGroup => ctaGroup.fields.condition === 'None')
  const loggedInCtas = contentfulContent.find(ctaGroup => ctaGroup.fields.condition === 'Logged in')
  const hasOrgCtas = contentfulContent.find(ctaGroup => ctaGroup.fields.condition === 'Has organization')

  if (isLoggedIn && hasOrganization && hasOrgCtas) {
    return <CtaButtons contentfulContent={hasOrgCtas} location={location} />
  }

  if (isLoggedIn && loggedInCtas) {
    return <CtaButtons contentfulContent={loggedInCtas} location={location} />
  }

  if (defaultCtas) {
    const {primary, secondary} = defaultCtas.fields

    return (
      <div className={`CtaForm${location !== 'hero' ? ' CTAForm-footer' : ''}`}>
        <form action={primary.fields.href} method="get" acceptCharset="UTF-8" aria-label={primary.fields.text}>
          <input type="hidden" name="source" value="form-home-signup" />

          <FormControl className="CtaFormControl">
            <ThemeProvider colorMode="light" className="CtaFormControl-container">
              <div className="CtaFormControl-field-wrap">
                <FormControl.Label className="CtaFormControl-label" htmlFor={`${location}_user_email`}>
                  Enter your email
                </FormControl.Label>

                <TextInput
                  className="CtaFormControl-input"
                  id={`${location}_user_email`}
                  type="email"
                  autoComplete="email"
                  spellCheck="false"
                  name="user_email"
                  placeholder="you@domain.com"
                />
              </div>

              <Button
                className={`CtaForm-primaryAction CtaFormControl-button ${location === 'hero' ? 'js-hero-action' : ''}`}
                type="submit"
                variant="primary"
                hasArrow={false}
                {...getAnalyticsEvent({action: primary.fields.text, tag: 'button', context: 'CTAs', location})}
              >
                {primary.fields.text}
              </Button>
            </ThemeProvider>
          </FormControl>
        </form>

        {secondary ? (
          <Button
            className={`CtaForm-secondaryAction CtaForm-nextToFormAction ${
              location === 'hero' ? 'js-hero-action' : ''
            }`}
            as="a"
            href={secondary.fields.href}
            hasArrow={false}
            {...getAnalyticsEvent({action: secondary.fields.text, tag: 'button', context: 'CTAs', location})}
          >
            {secondary.fields.text}
          </Button>
        ) : null}
      </div>
    )
  }

  return null
}
