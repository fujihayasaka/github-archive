import {Heading, Link} from '@primer/react'

import styles from './SidebarOrganizations.module.css'

function SidebarOrganizations() {
  return (
    <div className={styles.Box}>
      <Heading as="h2" className={styles.Heading}>
        Organizations
      </Heading>
      <div className={styles.Box_1}>
        {ORGANIZATIONS.map(a => {
          return (
            <Link key={a.id} href={a.href} aria-label={a.aria} className={styles.Link}>
              <img key={a.id} src={a.src} alt="" className={styles.Box_2} />
            </Link>
          )
        })}
      </div>
    </div>
  )
}

const ORGANIZATIONS = [
  {
    id: 0,
    src: 'https://avatars.githubusercontent.com/u/9919?s=88&v=4',
    href: 'https://github.com/github',
    aria: 'github',
  },
  {
    id: 1,
    src: 'https://avatars.githubusercontent.com/u/7143434?s=88&v=4',
    href: 'https://github.com/primer',
    aria: 'primer',
  },
]

export default SidebarOrganizations
