import {TypographyIcon} from '@primer/octicons-react'
import styles from './ThemeVisual.module.css'

type ThemeVisualProps = {
  theme?: 'light' | 'dark' | 'dark_dimmed'
}

// set the mode to light if the theme is light, otherwise set it to dark
function getMode(theme: string) {
  if (theme === 'light') {
    return 'light'
  } else if (theme === 'dark' || theme === 'dark_dimmed') {
    return 'dark'
  }
  return 'light'
}

function ThemeVisual({theme = 'light'}: ThemeVisualProps) {
  const mode = getMode(theme)
  return (
    <div className={styles.themeVisual} data-color-mode={mode} data-dark-theme={theme} data-light-theme={theme}>
      <TypographyIcon />
    </div>
  )
}

export {ThemeVisual}
export type {ThemeVisualProps}
