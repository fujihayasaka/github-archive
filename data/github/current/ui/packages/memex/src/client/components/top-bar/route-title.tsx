import {ArrowLeftIcon} from '@primer/octicons-react'
import {Heading} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {useViews} from '../../hooks/use-views'
import {Link} from '../../router'
import styles from './route-title.module.css'

export const RouteTitle = ({title}: {title: string}) => {
  const {returnToViewLinkTo} = useViews()

  return (
    <div className={styles.Box}>
      <Link to={returnToViewLinkTo} aria-label="Return to project view">
        <Octicon icon={ArrowLeftIcon} size={24} className={styles.Octicon} />
      </Link>
      <Heading as="h1" className={styles.Heading}>
        {title}
      </Heading>
    </div>
  )
}
