import {isLoggedIn} from '@github-ui/client-env'
import {getCookie} from '@github-ui/cookies'

export function updateHtmlHighContrastMode() {
  if (isLoggedIn()) return

  const lightHighContrast = getCookie('increase_contrast_light')
  const darkHighContrast = getCookie('increase_contrast_dark')

  document.documentElement.setAttribute(
    'data-light-theme',
    lightHighContrast?.value === 'enabled' ? 'light_high_contrast' : 'light',
  )
  document.documentElement.setAttribute(
    'data-dark-theme',
    darkHighContrast?.value === 'enabled' ? 'dark_high_contrast' : 'dark',
  )
}
