import {appEnv} from './utils'

export interface TestIdProps {
  /** Test ID to be queried by automated testing suites */
  'data-testid'?: string
}

export const testIdProps = (value: string): TestIdProps => {
  // Omit data-testid attribute in production.
  if (appEnv() === 'production') return {}

  // Non-production servers will get data-testid attributes in the DOM.
  return {'data-testid': value}
}
