import {SkeletonBox} from '@primer/react/experimental'
import {clsx} from 'clsx'
import type {ReactNode} from 'react'
import React from 'react'

import styles from './ServiceView.module.css'

/* <ServiceView.Container> */
interface ServiceContainerProps {
  children: ReactNode
  empty?: boolean
}

function ServiceContainer({children, empty}: ServiceContainerProps) {
  const bannerElements: ReactNode[] = []
  const otherChildren: ReactNode[] = []

  const childrenArray = React.Children.toArray(children)
  for (const child of childrenArray) {
    if (React.isValidElement(child) && child.type === ServiceBanner) {
      bannerElements.push(child)
    } else {
      otherChildren.push(child)
    }
  }

  return (
    <div className={styles.scrollContainer}>
      <div className={styles.contentContainer}>
        {bannerElements}
        <div className={clsx(styles.content, {[styles.empty]: empty})}>{otherChildren}</div>
      </div>
    </div>
  )
}

/* <ServiceView.Banner> */
interface ServiceBannerProps {
  children: ReactNode
}

function ServiceBanner({children}: ServiceBannerProps) {
  return <div className={styles.banner}>{children}</div>
}

/* <ServiceView.Header> */
interface ServiceHeaderProps {
  children: ReactNode
}

function ServiceHeader({children}: ServiceHeaderProps) {
  return <div className={styles.serviceHeader}>{children}</div>
}

/* <ServiceView.Section> */
interface ServiceSectionProps {
  children: ReactNode
}

function ServiceSection({children}: ServiceSectionProps) {
  return <section className={styles.section}>{children}</section>
}

/* <ServiceView.Icon> */

interface ServiceIconProps {
  icon: ReactNode
}

function Icon({icon}: ServiceIconProps) {
  return <div className={styles.serviceIcon}>{icon}</div>
}

/* <ServiceView.Title> */

interface ServiceTitleProps {
  children: ReactNode
}

function Title({children}: ServiceTitleProps) {
  return <h2 className={styles.serviceTitle}>{children}</h2>
}

/* <ServiceView.Description> */

interface ServiceDescriptionProps {
  children: ReactNode
}

function Description({children}: ServiceDescriptionProps) {
  return <p className={styles.serviceDescription}>{children}</p>
}

/* <ServiceView.Section.Title> */

interface SectionTitleProps {
  children: ReactNode
}

function SectionTitle({children}: SectionTitleProps) {
  return <h3 className={styles.sectionTitle}>{children}</h3>
}

/* <ServiceView.Section.Grid.Empty> */

interface ServiceGridEmptyProps {
  children: ReactNode
}

function SectionGridEmpty({children}: ServiceGridEmptyProps) {
  return <div className={styles.sectionGridEmpty}>{children}</div>
}

/* <ServiceView.Section.Grid> */

interface ServiceGridProps {
  children?: ReactNode
  loading?: boolean
}

function SectionGrid({children, loading = false}: ServiceGridProps) {
  if (loading) {
    return (
      <div className={styles.sectionGrid} data-testid="service-view-skeleton">
        {[...Array(3)].map((_, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <SkeletonBox key={index} className={styles.skeletonCard} />
        ))}
      </div>
    )
  }

  const childArray = React.Children.toArray(children)

  const emptyComponent = childArray.find(child => React.isValidElement(child) && child.type === SectionGridEmpty)
  const gridItems = childArray.filter(child => !(React.isValidElement(child) && child.type === SectionGridEmpty))

  // If we have no grid items but we have an empty component
  if (gridItems.length === 0 && emptyComponent) {
    return <>{emptyComponent}</>
  }

  return <div className={styles.sectionGrid}>{gridItems}</div>
}

SectionGrid.Empty = SectionGridEmpty
ServiceSection.Title = SectionTitle
ServiceSection.Grid = SectionGrid

interface ServiceViewNamespace {
  Icon: React.FC<{icon: React.ReactNode}>
  Title: React.FC<{children: React.ReactNode}>
  Description: React.FC<{children: React.ReactNode}>
  Container: typeof ServiceContainer
  Banner: typeof ServiceBanner
  Header: typeof ServiceHeader
  Section: typeof ServiceSection & {
    Title: React.FC<{children: React.ReactNode}>
    Grid: typeof SectionGrid & {
      Empty: React.FC<{children: React.ReactNode}>
    }
  }
}

const ServiceView: ServiceViewNamespace = {
  Icon,
  Title,
  Description,
  Container: ServiceContainer,
  Banner: ServiceBanner,
  Header: ServiceHeader,
  Section: ServiceSection,
}

export default ServiceView
