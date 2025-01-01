import {clsx} from 'clsx'
import styles from './InstallationAvatar.module.css'
import {GitHubAvatar} from '@github-ui/github-avatar'

export interface InstallationAvatarProps {
  icon_url: string
  icon_background_color?: string
  variant?: 'medium' | 'small'
}

const WHITE = 'ffffff'

const VARIANT_OPTIONS = {
  small: {icon_size: 10, styling: styles.installationAvatarSmall},
  medium: {icon_size: 24, styling: styles.installationAvatar},
}

export function InstallationAvatar({
  icon_url,
  icon_background_color = WHITE,
  variant = 'medium',
}: InstallationAvatarProps) {
  return (
    <div
      data-testid="installation-avatar"
      style={{backgroundColor: `#${icon_background_color}`}}
      className={clsx(
        VARIANT_OPTIONS[variant].styling,
        icon_background_color === WHITE ? styles['installationAvatar--black'] : styles['installationAvatar--white'],
        'rounded-3 flex-shrink-0',
      )}
    >
      <GitHubAvatar
        src={icon_url}
        size={VARIANT_OPTIONS[variant].icon_size}
        square
        className={clsx(styles.installationAvatarImg)}
      />
    </div>
  )
}
