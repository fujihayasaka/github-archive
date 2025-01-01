import {IconButton} from '@primer/react'
import {SlidersIcon} from '@primer/octicons-react'
import {forwardRef} from 'react'
import styles from './AppearanceSettingsNavButton.module.css'

export const AppearanceSettingsNavButton = forwardRef<HTMLButtonElement>((props, ref) => (
  <IconButton
    variant="invisible"
    icon={SlidersIcon}
    aria-label="Appearance settings"
    className={styles.NavButton}
    ref={ref}
    {...props}
  />
))
AppearanceSettingsNavButton.displayName = 'AppearanceSettingsNavButton'

export default AppearanceSettingsNavButton
