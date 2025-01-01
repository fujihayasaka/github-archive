import type {LaunchCodeProps} from '../LaunchCode'

export function getLaunchCodeProps(): LaunchCodeProps {
  return {
    email: 'monalisa@github.com',
    error: undefined,
    isDevEnv: true,
    launchCodeLength: 8,
    showLaunchCode: true,
    verificationToken: 12345678,
  }
}
