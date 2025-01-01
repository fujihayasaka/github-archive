import {Flash, Link, LinkButton} from '@primer/react'
import {BUTTON_LABELS} from '../constants/buttons'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {LABELS} from '../constants/labels'
import {loginPathWithReturnTo, signUpPathWithReturnTo} from '../utils/urls'

export const SignedOutBanner = () => {
  return (
    <Flash sx={{mt: '16px'}} variant={'warning'}>
      <LinkButton variant="primary" href={signUpPathWithReturnTo(ssrSafeLocation.href)}>
        {BUTTON_LABELS.signUp}
      </LinkButton>
      <span>
        <strong> {LABELS.signedOutBanner.signUp}</strong> {LABELS.signedOutBanner.signIn}{' '}
      </span>
      <Link href={loginPathWithReturnTo(ssrSafeLocation.href)}>{BUTTON_LABELS.signIn}</Link>
    </Flash>
  )
}
