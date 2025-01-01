import {FormControl, TextInput, ThemeProvider, Button} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

export interface CtaFormProps {
  location: string
}

const COPY = {
  form: {
    input: {
      label: 'Enter your email',
      placeholder: 'you@domain.com',
    },
    submit: {
      label: 'Sign up for GitHub',
      url: '/signup',
    },
    aria: {
      hero: 'Create your GitHub account',
      default: 'Sign up for GitHub',
    },
  },
  ctas: {
    preview: {
      label: 'Explore upcoming releases',
      url: '/features/preview',
    },
    copilot_loggedOut: {
      label: 'Try GitHub Copilot',
      url: '/github-copilot/pro?cft=copilot_lo.copilot_plans.cfi',
    },
    copilot_loggedIn: {
      label: 'Try Copilot Free',
      url: '/github-copilot/pro?cft=copilot_lo.copilot_plans.cfi',
    },
    enterprise: {
      label: 'Free Enterprise trial',
      url: '/account/enterprises/new',
    },
  },
} as const

const defaultProps: Partial<CtaFormProps> = {}

const CtaForm: React.FC<CtaFormProps> = props => {
  const {isLoggedIn, hasOrganization} = useRoutePayload<{isLoggedIn: boolean; hasOrganization: boolean}>()
  const initializedProps = {...defaultProps, ...props}
  const {location} = initializedProps

  return (
    <div className={`CtaForm${location !== 'hero' ? ' CTAForm-footer' : ''}`}>
      {isLoggedIn ? (
        <>
          {/* Logged in */}
          <Button
            className={`CtaForm-primaryAction ${location === 'hero' ? 'js-hero-action' : ''}`}
            as="a"
            href={hasOrganization ? COPY.ctas.enterprise.url : COPY.ctas.copilot_loggedIn.url}
            variant="primary"
            hasArrow={false}
            {...getAnalyticsEvent({
              action: hasOrganization ? 'try_enterprise' : 'try_copilot',
              tag: 'button',
              context: 'CTAs',
              location,
            })}
          >
            {hasOrganization ? COPY.ctas.enterprise.label : COPY.ctas.copilot_loggedIn.label}
          </Button>

          <Button
            className={`CtaForm-secondaryAction ${location === 'hero' ? 'js-hero-action' : ''}`}
            as="a"
            href={COPY.ctas.preview.url}
            hasArrow={false}
            {...getAnalyticsEvent({action: 'sign_up', tag: 'button', context: 'CTAs', location})}
          >
            {COPY.ctas.preview.label}
          </Button>
        </>
      ) : (
        <>
          {/* Logged out */}
          <form
            action={COPY.form.submit.url}
            method="get"
            acceptCharset="UTF-8"
            aria-label={location === 'hero' ? COPY.form.aria.hero : COPY.form.aria.default}
          >
            <input type="hidden" name="source" value="form-home-signup" />
            <FormControl className="CtaFormControl">
              <ThemeProvider colorMode="light" className="CtaFormControl-container">
                <div className="CtaFormControl-field-wrap">
                  <FormControl.Label className="CtaFormControl-label" htmlFor={`${location}_user_email`}>
                    {COPY.form.input.label}
                  </FormControl.Label>

                  <TextInput
                    className="CtaFormControl-input"
                    id={`${location}_user_email`}
                    type="email"
                    autoComplete="email"
                    spellCheck="false"
                    name="user_email"
                    placeholder={COPY.form.input.placeholder}
                  />
                </div>

                <Button
                  className={`CtaForm-primaryAction CtaFormControl-button ${
                    location === 'hero' ? 'js-hero-action' : ''
                  }`}
                  type="submit"
                  variant="primary"
                  hasArrow={false}
                  {...getAnalyticsEvent({action: 'sign_up', tag: 'button', context: 'CTAs', location})}
                >
                  {COPY.form.submit.label}
                </Button>
              </ThemeProvider>
            </FormControl>
          </form>

          <Button
            className={`CtaForm-secondaryAction CtaForm-nextToFormAction ${
              location === 'hero' ? 'js-hero-action' : ''
            }`}
            as="a"
            href={COPY.ctas.copilot_loggedOut.url}
            hasArrow={false}
            {...getAnalyticsEvent({action: 'try_copilot', tag: 'button', context: 'CTAs', location})}
          >
            {COPY.ctas.copilot_loggedOut.label}
          </Button>
        </>
      )}
    </div>
  )
}

export default CtaForm
