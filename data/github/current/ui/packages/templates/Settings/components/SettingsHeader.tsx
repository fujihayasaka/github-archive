import {PageHeader} from '@primer/react/experimental'

import styles from './SettingsHeader.module.css'

interface SettingsHeaderProps {
  title: string
  description?: string
  divider?: boolean
  isChild?: boolean
  parentLink?: string
  trailingAction?: React.ReactNode
  //todo add action
  //todo add leadingaction / isChild
}

const SettingsHeader = ({title, description, divider = false, trailingAction}: SettingsHeaderProps) => {
  return (
    <PageHeader
      sx={{
        pb: divider ? 2 : 0,
        borderBottom: divider ? '1px solid' : 0,
      }}
      className={styles.PageHeader}
    >
      <PageHeader.TitleArea>
        <PageHeader.Title as="h1" className={styles.PageHeader_Title}>
          {title}
        </PageHeader.Title>
      </PageHeader.TitleArea>
      {trailingAction ? <PageHeader.Actions>{trailingAction}</PageHeader.Actions> : null}
      {description && (
        <PageHeader.Description>
          <span className={styles.Text}>{description}</span>
        </PageHeader.Description>
      )}
    </PageHeader>
  )
}

export default SettingsHeader
