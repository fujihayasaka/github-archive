import {ActionList} from '@primer/react'
import {ArrowRightIcon} from '@primer/octicons-react'
import styles from './IssueTemplateItem.module.css'

import {Link} from '@github-ui/react-core/link'

type IssueTemplateItemProps = {
  filename: string
  onTemplateSelected: (filename: string) => void
  name: string
  link: string | null | undefined
  about?: string | null
  externalLink?: boolean
  trailingIcon?: JSX.Element
}

export const IssueTemplateItem = ({
  filename,
  onTemplateSelected,
  name,
  about,
  link,
  externalLink,
  trailingIcon,
}: IssueTemplateItemProps): JSX.Element => {
  // Navigation - be it react or hard nav - is handled by the Link component
  // this method should care only about additional actions
  const wrappedOnClick = (e: React.MouseEvent) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return
    if (!externalLink && !link) {
      e.preventDefault()
      e.stopPropagation()
    }

    onTemplateSelected(filename)
  }

  return (
    <ActionList.LinkItem
      as={Link}
      key={filename}
      to={link ?? '#'}
      target={externalLink ? '_blank' : undefined}
      onClick={wrappedOnClick}
      className={styles.templateItemContainer}
    >
      <span className={styles.actionListTitle}>{name}</span>
      <ActionList.Description variant="block">{about}</ActionList.Description>
      <ActionList.TrailingVisual>{trailingIcon ?? <ArrowRightIcon />}</ActionList.TrailingVisual>
    </ActionList.LinkItem>
  )
}
