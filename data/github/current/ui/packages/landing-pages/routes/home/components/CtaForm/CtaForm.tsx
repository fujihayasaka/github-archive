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
  },
  preview: {
    label: 'Explore upcoming releases',
    url: '/features/preview',
  },
  copilot: {
    label: 'Try GitHub Copilot',
    url: '/features/copilot',
  },
}

const defaultProps: Partial<CtaFormProps> = {}

const CtaForm: React.FC<CtaFormProps> = props => {
  const {isLoggedIn} = useRoutePayload<{isLoggedIn: boolean}>()

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
            href={COPY.copilot.url}
            variant="primary"
            hasArrow={false}
            {...getAnalyticsEvent({action: 'try_copilot', tag: 'button', context: 'CTAs', location})}
          >
            {COPY.copilot.label}
          </Button>

          <Button
            className={`CtaForm-secondaryAction ${location === 'hero' ? 'js-hero-action' : ''}`}
            as="a"
            href={COPY.preview.url}
            hasArrow={false}
            {...getAnalyticsEvent({action: 'sign_up', tag: 'button', context: 'CTAs', location})}
          >
            {COPY.preview.label}
          </Button>
        </>
      ) : (
        <>
          {/* Logged out */}
          <form action={COPY.form.submit.url} method="get" acceptCharset="UTF-8" aria-label={COPY.form.submit.label}>
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
            href={COPY.copilot.url}
            hasArrow={false}
            {...getAnalyticsEvent({action: 'try_copilot', tag: 'button', context: 'CTAs', location})}
          >
            {COPY.copilot.label}
          </Button>
        </>
      )}
    </div>
  )
}

export default CtaForm
