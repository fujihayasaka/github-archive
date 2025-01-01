import {Link} from '@primer/react'

import styles from './Footer.module.css'

const SUPPORT_ITEMS = [
  {
    id: 0,
    name: 'About',
    href: 'https://github.com/about',
  },
  {
    id: 1,
    name: 'Terms',
    href: 'https://docs.github.com/en/site-policy/github-terms/github-terms-of-service',
  },
  {
    id: 2,
    name: 'Privacy',
    href: 'https://docs.github.com/site-policy/privacy-policies/github-privacy-statement',
  },
  {
    id: 3,
    name: 'Docs',
    href: 'https://docs.github.com/en',
  },
  {
    id: 4,
    name: 'Support',
    href: 'https://support.github.com/request/landing',
  },
  {
    id: 5,
    name: 'Manage cookies',
    href: 'https://github.com',
  },
]

function Footer() {
  return (
    <footer className={styles.Box}>
      <nav>
        <ul className={styles.Box_1}>
          {SUPPORT_ITEMS.map(item => {
            return (
              <li key={item.id}>
                <Link href={item.href} muted className={styles.Link}>
                  {item.name}
                </Link>
              </li>
            )
          })}
        </ul>
      </nav>
    </footer>
  )
}

export default Footer
