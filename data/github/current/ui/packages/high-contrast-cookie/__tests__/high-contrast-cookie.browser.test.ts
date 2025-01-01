import {beforeEach, describe, it} from '@github-ui/tests'
import {assert} from '@github-ui/tests/browser'
import {updateHtmlHighContrastMode} from '../high-contrast-cookie'
import {deleteCookie, setCookie} from '@github-ui/cookies'
import {mockClientEnv} from '@github-ui/client-env/mock'

describe('high-contrast-cookie', () => {
  beforeEach(() => {
    document.documentElement.setAttribute('data-light-theme', 'light')
    document.documentElement.setAttribute('data-dark-theme', 'dark')
  })

  it('updates both themes', () => {
    setCookie('increase_contrast_light', 'enabled')
    setCookie('increase_contrast_dark', 'enabled')

    updateHtmlHighContrastMode()

    assert.equal(document.documentElement.getAttribute('data-light-theme'), 'light_high_contrast')
    assert.equal(document.documentElement.getAttribute('data-dark-theme'), 'dark_high_contrast')
  })

  it('updates only light', () => {
    setCookie('increase_contrast_light', 'enabled')
    setCookie('increase_contrast_dark', 'disabled')

    updateHtmlHighContrastMode()

    assert.equal(document.documentElement.getAttribute('data-light-theme'), 'light_high_contrast')
    assert.equal(document.documentElement.getAttribute('data-dark-theme'), 'dark')
  })

  it('updates only dark', () => {
    setCookie('increase_contrast_light', 'disabled')
    setCookie('increase_contrast_dark', 'enabled')

    updateHtmlHighContrastMode()

    assert.equal(document.documentElement.getAttribute('data-light-theme'), 'light')
    assert.equal(document.documentElement.getAttribute('data-dark-theme'), 'dark_high_contrast')
  })

  it('does not update when cookies are disabled', () => {
    setCookie('increase_contrast_light', 'disabled')
    setCookie('increase_contrast_dark', 'disabled')

    updateHtmlHighContrastMode()

    assert.equal(document.documentElement.getAttribute('data-light-theme'), 'light')
    assert.equal(document.documentElement.getAttribute('data-dark-theme'), 'dark')
  })

  it('does not update when cookies are unset', () => {
    deleteCookie('increase_contrast_light')
    deleteCookie('increase_contrast_dark')

    updateHtmlHighContrastMode()

    assert.equal(document.documentElement.getAttribute('data-light-theme'), 'light')
    assert.equal(document.documentElement.getAttribute('data-dark-theme'), 'dark')
  })

  it('does not update when user is logged in', () => {
    mockClientEnv({
      login: 'some-user',
    })

    setCookie('increase_contrast_light', 'enabled')
    setCookie('increase_contrast_dark', 'enabled')

    updateHtmlHighContrastMode()

    assert.equal(document.documentElement.getAttribute('data-light-theme'), 'light')
    assert.equal(document.documentElement.getAttribute('data-dark-theme'), 'dark')
  })
})
