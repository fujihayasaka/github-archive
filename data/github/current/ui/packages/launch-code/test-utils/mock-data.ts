import type {LaunchCodeProps} from '../LaunchCode'

export function getLaunchCodeProps(): LaunchCodeProps {
  return {
    email: 'monalisa@github.com',
    error: undefined,
    isDevEnv: true,
    launchCodeLength: 8,
    showLaunchCode: true,
    verificationToken: 12345678,
    hiddenFieldsParams: {
      return_to: '',
      invitation_token: '',
      repo_invitation_token: '',
      plan: '',
      verification: '',
      setup_organization: '',
      trial_acquisition_channel: '',
    },
    resendVerificationPath: '/resend_verification',
    updateEmailPath: '/update_email',
  }
}
