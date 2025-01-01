import {NavLink} from '@github-ui/react-core/link'

import styles from './styles.module.css'
import {reactSandboxFutureIdRoute} from '../routes/id-route'
import {reactSandboxFutureIndexRoute} from '../routes/index-route'

export function FooterLinks() {
  return (
    <div>
      <ul className={styles.footerlinks}>
        <li className={styles.footerlinksListItem}>
          <NavLink to={reactSandboxFutureIndexRoute.generatePath({})}>Index page</NavLink>
        </li>
        <li className={styles.footerlinksListItem}>
          <NavLink to={reactSandboxFutureIdRoute.generatePath({id: '1'})}>Page 1</NavLink>
        </li>
        <li className={styles.footerlinksListItem}>
          <NavLink to={reactSandboxFutureIdRoute.generatePath({id: '2'})}>Page 2</NavLink>
        </li>
      </ul>
    </div>
  )
}
