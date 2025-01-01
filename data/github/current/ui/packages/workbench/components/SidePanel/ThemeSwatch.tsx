import {clsx} from 'clsx'

import styles from './ThemeSwatch.module.css'

interface ThemeSwatchProps {
  color: string
  size: 'small' | 'large'
}

export const ThemeSwatch = ({color, size}: ThemeSwatchProps) => {
  return (
    <div
      className={clsx(styles.container, {
        [styles.small]: size === 'small',
        [styles.large]: size === 'large',
      })}
      style={{
        '--swatch-color': color,
      }}
    />
  )
}
