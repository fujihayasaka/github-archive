// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {getTitleForStatus} from '../../future/use-set-title-on-response-error'

describe('getTitleForStatus', () => {
  afterEach(() => {
    document.body.classList.remove('logged-out')
  })

  it('returns title for 404', () => {
    const actualTitle = getTitleForStatus(404)
    const expectedTitle = '404 Page not found'

    expect(actualTitle).toBe(expectedTitle)
  })

  it('returns title for 500', () => {
    const actualTitle = getTitleForStatus(500)
    const expectedTitle = '500 Internal server error'

    expect(actualTitle).toBe(expectedTitle)
  })

  it('returns title for other status code', () => {
    const actualTitle = getTitleForStatus(422)
    const expectedTitle = 'Error 422'

    expect(actualTitle).toBe(expectedTitle)
  })

  it('appends " · GitHub" to title for logged-out users', () => {
    document.body.classList.add('logged-out')

    const actualTitle = getTitleForStatus(404)
    const expectedTitle = '404 Page not found · GitHub'

    expect(actualTitle).toBe(expectedTitle)
  })
})
