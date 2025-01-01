import {SearchIcon} from '@primer/octicons-react'
import {Button, Stack} from '@primer/react'
import type {ReactElement, ReactNode} from 'react'
import {isValidElement, useState} from 'react'
import {Link} from 'react-router-dom'

import styles from './ServiceView.module.css'

interface ServiceViewProps {
  name: string /* Name of the service "Bananas" */
  entity: 'space' /* Usually the singular of the service name "banana" */
  entityIcon?: ReactNode /* Optional service icon */
  description: string /* A description for the empty state of the service */
  onCreate: () => void /* Create button event */
  children?: ReactNode
}

function isChildWithTitle(child: ReactNode): child is ReactElement<{title: string}> {
  return isValidElement<{title: string}>(child) && typeof child.props.title === 'string'
}

export function ServiceView({name, entity, entityIcon, description, onCreate, children}: ServiceViewProps) {
  const [searchQuery, setSearchQuery] = useState('')
  // Ensure `childElements` is a typed array of ReactNode
  const childElements: ReactNode[] = children ? (Array.isArray(children) ? (children as ReactNode[]) : [children]) : []
  const totalChildrenCount = childElements.length

  const filteredChildren = childElements
    .map((child: ReactNode) => {
      if (isChildWithTitle(child)) {
        const dataTitle = child.props.title.toLowerCase()
        if (dataTitle.includes(searchQuery.toLowerCase())) {
          return child
        }
      }
      return null
    })
    .filter(Boolean)

  const totalFilteredCount = filteredChildren.length

  return (
    <div className={styles.scrollContainer}>
      {totalChildrenCount === 0 ? (
        <div className={styles.emptyStateContainer}>
          <Stack gap="none">
            {entityIcon ? <div className={styles.entityIcon}>{entityIcon}</div> : null}
            <h2 className={styles.pageTitle}>{name}</h2>
          </Stack>
          <p className={styles.description}>{description}</p>
          <Button variant="primary" onClick={onCreate}>
            New {entity.toLowerCase()}
          </Button>
        </div>
      ) : (
        <div className={styles.container}>
          <div className={styles.header}>
            <h2 className={styles.pageTitle}>{name}</h2>
            <Button variant="primary" onClick={onCreate}>
              New {entity.toLowerCase()}
            </Button>
          </div>
          <div className={styles.search}>
            <SearchIcon className={styles.searchIcon} />
            <input
              className={styles.searchInput}
              aria-label={`Search ${name.toLowerCase()}`}
              placeholder={`Search ${name.toLowerCase()}`}
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
            />
          </div>
          {totalFilteredCount === 0 ? (
            <p className={styles.emptyGrid}>No {name.toLowerCase()} found matching your search.</p>
          ) : (
            <div className={styles.grid}>{filteredChildren}</div>
          )}
        </div>
      )}
    </div>
  )
}

interface ServiceItemProps extends React.HTMLProps<HTMLAnchorElement> {
  title: string
  href: string
  children: ReactNode
}

export function ServiceItem({title, href, children, ...rest}: ServiceItemProps) {
  return (
    <Link {...rest} to={href} className={styles.card} data-title={title}>
      {children}
    </Link>
  )
}
