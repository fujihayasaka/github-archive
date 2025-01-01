import {Link, IconButton, Heading} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'
import {PencilIcon} from '@primer/octicons-react'

import styles from './CustomReadme.module.css'

function Readme() {
  return (
    <div className={styles.Box}>
      <Heading as="h2" className={styles.Heading}>
        Welcome
      </Heading>
      <div className={styles.Box_1}>
        <div className={styles.Box_2}>
          <div className={styles.Box_3}>
            <Link href="https://github.com/mona" className={styles.Link}>
              mona
            </Link>{' '}
            <span className={styles.Box_4}>/</span>{' '}
            <Link href="https://github.com/mona/mona/readme.md" className={styles.Link}>
              README.md
            </Link>
          </div>
          <div>
            Hey there, I&apos;m Mona 🌟 At Github, I navigate the digital depths as the Chief Purr-ogramming Officer
            🐱🐙
          </div>
          My mission? To safeguard the open-source sea and entertain with my yarn ball antics.
          <div>Check out my latest open-source adventure below.</div>
          <div>=^..^=</div>
        </div>
        <div className={styles.Box_5}>
          <Tooltip aria-label="Edit">
            {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
            <IconButton unsafeDisableTooltip icon={PencilIcon} variant="invisible" aria-label="Edit" />
          </Tooltip>
        </div>
      </div>
    </div>
  )
}

export default Readme
