import {
  popNavigationBreadcrumb,
  pushNavigationBreadcrumb,
  renameCurrentNavigationBreadcrumb,
  replaceCurrentNavigationBreadcrumb,
  replaceNavigationBreadcrumbs,
} from '@github-ui/global-navigation'
import {Button, Heading} from '@primer/react'

import styles from './GlobalNavigation.module.css'

export function GlobalNavigationPage() {
  let crumbCount = 1

  function insertCrumb() {
    pushNavigationBreadcrumb({
      label: `Crumb ${crumbCount}`,
      href: '#',
    })

    crumbCount++
  }

  function removeCrumb() {
    popNavigationBreadcrumb()

    if (crumbCount > 1) {
      crumbCount--
    }
  }

  function replaceCrumbs() {
    const crumbs = [
      {label: 'Here', href: '#'},
      {label: 'are', href: '#'},
      {label: 'new', href: '#'},
      {label: 'crumbs', href: '#'},
    ]

    replaceNavigationBreadcrumbs(crumbs)
  }

  function replaceCurrentCrumb() {
    replaceCurrentNavigationBreadcrumb({
      label: 'Dashboard',
      href: '/',
    })
  }

  function renameCrumb() {
    renameCurrentNavigationBreadcrumb('Fish sticks')
  }

  return (
    <>
      <Heading as="h1">Global Navigation Demo</Heading>
      <p>This demonstrates how we can interact with the Rails-based Global Nav from within a React app or component.</p>

      <Button className={styles.button} onClick={insertCrumb}>
        Add breadcrumb
      </Button>

      <Button className={styles.button} onClick={removeCrumb}>
        Remove crumb
      </Button>

      <Button className={styles.button} onClick={replaceCrumbs}>
        Replace all crumbs
      </Button>

      <Button className={styles.button} onClick={replaceCurrentCrumb}>
        Replace the current page crumb
      </Button>

      <Button className={styles.button} onClick={renameCrumb}>
        Rename the current page crumb
      </Button>
    </>
  )
}
