import type {ReactNode} from 'react'
import React from 'react'
import {Link} from 'react-router-dom'
import {Icon as PacerIcon, type IconColor} from './Icon'

import styles from './Card.module.css'
import type {IconName} from './CustomIcon'
import {clsx} from 'clsx'

type IconProps = {
  icon: React.ElementType | IconName
  color?: IconColor
}

type ImageProps = {
  img: string
  alt?: string // optional alt text for accessibility
}

type HeadingProps = {
  children: ReactNode
}

type DescriptionProps = {
  children: ReactNode
}

type MenuProps = {
  children: ReactNode
}

type MetadataProps = {
  children: ReactNode
}

type CardLinkProps = {
  href: string
  children: ReactNode
} & Omit<React.ComponentProps<typeof Link>, 'to'>

type CardButtonProps = {
  onClick?: () => void
  children: ReactNode
} & Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'>

type CardProps = CardLinkProps | CardButtonProps

const Card = (props: CardProps) => {
  let icon: ReactNode = null
  let image: ReactNode = null
  let heading: ReactNode = null
  let description: ReactNode = null
  let metadata: ReactNode = null
  let menu: ReactNode = null

  const childArray = React.Children.toArray(props.children)

  for (const child of childArray) {
    if (!React.isValidElement(child)) continue

    if (child.type === Icon) {
      icon = child
    } else if (child.type === Image) {
      image = child
    } else if (child.type === Heading) {
      heading = child
    } else if (child.type === Description) {
      description = child
    } else if (child.type === Metadata) {
      metadata = child
    } else if (child.type === Menu) {
      menu = child
    }
  }

  const content = (
    <>
      <div className={clsx(styles.itemHeader, image && styles.edgeToEdge)}>{icon || image}</div>
      <div className={styles.itemMain}>
        <div className={styles.itemContent}>
          {heading}
          {description}
        </div>
        <div className={styles.itemMetadata}>{metadata}</div>
      </div>
    </>
  )

  if ('href' in props) {
    const {href, ...rest} = props
    return (
      <div className={styles.cardContainer}>
        <Link {...rest} to={href} className={styles.cardContent}>
          {content}
        </Link>
        {menu ? <div className={styles.cardMenu}>{menu}</div> : null}
      </div>
    )
  }

  const {onClick, ...rest} = props
  return (
    <div className={styles.cardContainer}>
      <button {...rest} className={styles.cardContent} onClick={onClick}>
        {content}
      </button>
      {menu ? <div className={styles.cardMenu}>{menu}</div> : null}
    </div>
  )
}

// <Card.Icon icon={SomeIcon} />
const Icon = ({icon, color}: IconProps) => {
  return <PacerIcon icon={icon} hasBackground color={color} size={16} />
}

// <Card.Image />
const Image = ({img, alt = ''}: ImageProps) => {
  return <img src={img} alt={alt} className={styles.itemImage} />
}

// <Card.Heading>Heading</Card.Heading>
const Heading = ({children}: HeadingProps) => {
  return <h3 className={styles.itemHeaderTitle}>{children}</h3>
}

// <Card.Description>Description</Card.Description>
const Description = ({children}: DescriptionProps) => {
  return <p className={styles.itemHeaderDescription}>{children}</p>
}

// <Card.Menu><ActionList /></Card.Menu>
const Menu = ({children}: MenuProps) => {
  return <>{children}</>
}

// <Card.Metadata>Metadata</Card.Metadata>
const Metadata = ({children}: MetadataProps) => {
  return <div className={styles.itemMetadataItem}>{children}</div>
}

Card.Icon = Icon
Card.Image = Image
Card.Heading = Heading
Card.Description = Description
Card.Menu = Menu
Card.Metadata = Metadata

export {Card}
