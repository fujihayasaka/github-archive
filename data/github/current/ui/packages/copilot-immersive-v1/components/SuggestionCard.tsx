import {SafeHTMLDiv, type SafeHTMLString} from '@github-ui/safe-html'
// eslint-disable-next-line import/no-namespace
import * as icons from '@primer/octicons-react'

import classes from './SuggestionCard.module.css'

type SuggestionCardProps = {
  titleHtml: SafeHTMLString
  icon: string
  color: string
  onClick: () => void
}

const isIconName = (name: string): name is keyof typeof icons => name in icons

/** Get the `Icon` component for a kebab-case icon name. */
function getIcon(icon: string) {
  const iconName = `${icon.replaceAll(/(?:^|-)(\w)/g, (_, letter: string) => letter.toUpperCase())}Icon`
  const iconComponent = isIconName(iconName) ? icons[iconName] : undefined
  return iconComponent
}

export function SuggestionCard({titleHtml, icon, color, onClick}: SuggestionCardProps) {
  const Icon = getIcon(icon)

  return (
    <button className={classes.suggestionButton} onClick={onClick}>
      {Icon && (
        <div className={classes.icon} style={{color}}>
          <Icon />
        </div>
      )}
      <SafeHTMLDiv html={titleHtml} />
    </button>
  )
}
