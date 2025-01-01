import {getEnv} from '@github-ui/client-env'

export const getLocale = () => {
  return getEnv().locale
}
