import {mockClientEnv} from '@github-ui/client-env/mock'
import {getLocale} from '../get-locale'

describe('getLocale', () => {
  it('should use the locale from the client config', () => {
    mockClientEnv({locale: 'en-US'})
    expect(getLocale()).toEqual('en-US')
  })
})
