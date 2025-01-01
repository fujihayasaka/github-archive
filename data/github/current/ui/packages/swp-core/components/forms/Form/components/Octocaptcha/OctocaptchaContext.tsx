import {createContext} from 'react'

type OctocaptchaContextValue = {
  /**
   * The hostname of the octocaptcha instance to use, e.g. "octocaptcha.com"
   */
  hostName: string

  /**
   * Octocaptcha uses the `origin_page` parameter to load the right configuration
   * (e.g. api keys, feature flags, metrics, etc.).
   */
  originPage?: string
}

export const OctocaptchaContext = createContext<OctocaptchaContextValue>({hostName: ''})
