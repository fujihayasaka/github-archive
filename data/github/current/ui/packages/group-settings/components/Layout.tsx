import type {PropsWithChildren} from 'react'
import {Breadcrumbs, Heading} from '@primer/react'
import {Pagehead} from '@primer/react/deprecated'
import {Link} from '@github-ui/react-core/link'
import {useBasePath} from '../contexts/BasePathContext'
import {useReadOnly} from '../contexts/ReadOnlyContext'
import {useOrganization} from '../contexts/OrganizationContext'
import type {PAGE} from '../types'
import styles from './Layout.module.css'

export type LayoutProps = PropsWithChildren<{
  page: PAGE
  name?: string
}>

function GroupBreadcrumbs({page, name}: Pick<LayoutProps, 'page' | 'name'>) {
  const basePath = useBasePath()
  const organization = useOrganization()
  const displayName = page === 'New' ? 'New group' : name || organization.name
  return (
    <Breadcrumbs>
      <Breadcrumbs.Item as={Link} to={basePath} selected={page === 'List'}>
        Home
      </Breadcrumbs.Item>
      {page !== 'List' ? (
        <>
          <Breadcrumbs.Item
            as={Link}
            to={page === 'New' ? '' : `${basePath}/${name}`}
            selected={['New', 'Show'].includes(page)}
          >
            {displayName}
          </Breadcrumbs.Item>
          {page === 'Review' ? (
            <Breadcrumbs.Item href={`${basePath}/${name}/review`} selected={page === 'Review'}>
              Review changes
            </Breadcrumbs.Item>
          ) : null}
        </>
      ) : null}
    </Breadcrumbs>
  )
}

function Header({page}: Pick<LayoutProps, 'page'>) {
  const readOnly = useReadOnly()

  const TITLES: Record<PAGE, string> = {
    ['List']: 'Groups',
    ['New']: 'New group',
    ['Show']: `${readOnly ? 'View' : 'Edit'} group`,
    ['Review']: 'Review changes',
  }
  return (
    <Pagehead data-hpc className={styles.Pagehead}>
      <div>
        <Heading as="h2" className="h3">
          {TITLES[page]}
        </Heading>
        {page === 'List' ? (
          <span className="color-fg-muted pt-3">
            Manage access and settings for groups of repositories in your organization.
          </span>
        ) : null}
      </div>
    </Pagehead>
  )
}

export function Layout({page, name, children}: LayoutProps) {
  return (
    <>
      <GroupBreadcrumbs page={page} name={name} />
      <Header page={page} />
      {children}
    </>
  )
}
