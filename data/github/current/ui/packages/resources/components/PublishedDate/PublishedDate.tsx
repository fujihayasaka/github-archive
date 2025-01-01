import {Text} from '@primer/react-brand'
import {getLocale} from '@github-ui/get-locale'

import {formatPublishedDate} from '../../lib/utils'
import styles from './PublishedDate.module.css'

export type PublishedDateProps = {
  publishedDate: string
  updatedDate?: string
}

export const PublishedDate = ({publishedDate, updatedDate}: PublishedDateProps) => {
  const locale = getLocale()

  const formattedPublishedDate = formatPublishedDate(publishedDate, locale)
  const formattedUpdatedDate = formatPublishedDate(updatedDate, locale)

  return (
    formattedPublishedDate && (
      <Text as="p" className={styles.date}>
        <time dateTime={publishedDate}>{formattedPublishedDate}</time>
        {updatedDate && updatedDate !== publishedDate && (
          <>
            {` • updated `}
            <time dateTime={updatedDate}>{formattedUpdatedDate}</time>
          </>
        )}
      </Text>
    )
  )
}
