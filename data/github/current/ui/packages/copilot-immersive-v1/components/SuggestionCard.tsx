import type {ReactNode} from 'react'

import classes from './SuggestionCard.module.css'

type SuggestionCardProps = {
  title: string | ReactNode
  icon: ReactNode
  color: string
  onClick: () => void
}

export function SuggestionCard({title, icon, color, onClick}: SuggestionCardProps) {
  return (
    <button className={classes.suggestionButton} onClick={onClick}>
      <div className={classes.icon} style={{color}}>
        {icon}
      </div>
      <div>{title}</div>
    </button>
  )
}
