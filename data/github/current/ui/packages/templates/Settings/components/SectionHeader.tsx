import {PageHeader} from '@primer/react/experimental'

import styles from './SectionHeader.module.css'

interface SectionsHeaderProps {
  title: string
  description?: string
  divider?: boolean
  //todo add action here
  //
}

const SectionHeader = ({title, description, divider = false}: SectionsHeaderProps) => {
  return (
    <PageHeader
      sx={{
        borderBottom: divider ? '1px solid' : 0,
      }}
      className={styles.PageHeader}
    >
      <PageHeader.TitleArea>
        <PageHeader.Title className={styles.PageHeader_Title}>{title}</PageHeader.Title>
      </PageHeader.TitleArea>
      {description && (
        <PageHeader.Description>
          <span className={styles.Text}>{description}</span>
        </PageHeader.Description>
      )}
    </PageHeader>
  )
}

export default SectionHeader
