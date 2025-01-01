import {Heading, Link} from '@primer/react'
import {Pagehead} from '@primer/react/deprecated'
import {clsx} from 'clsx'

import styles from './Header.module.css'

type Props = {
  title: string
  description?: string | JSX.Element
  feedbackLink: {
    text: string
    url: string
  }
}

function Header({title, description, feedbackLink}: Props): JSX.Element {
  return (
    <Pagehead className={styles.Pagehead}>
      <div className={styles.Box}>
        <Heading as="h2" className={clsx('h1-override-shared-component', styles.Heading)}>
          {title}
        </Heading>
        <div className={styles.Box_1}>
          {feedbackLink.url && (
            <Link href={feedbackLink.url} className={styles.Link}>
              {feedbackLink.text}
            </Link>
          )}
        </div>
      </div>
      {description &&
        (typeof description === 'string' ? <span className={styles.Text}>{description}</span> : description)}
    </Pagehead>
  )
}

Header.displayName = 'PageLayout.Header'

export default Header
