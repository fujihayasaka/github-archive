import {Link} from '@primer/react'
import type {HTMLAttributes} from 'react'

import {useLabelId} from '../LabelIdContext'

type StaticMetadataProps = {
  children: React.ReactNode
} & HTMLAttributes<HTMLSpanElement>

type LinkMetadataProps = StaticMetadataProps & {
  /** Optional URL to navigate to on click. */
  href: string
}

type ActionMetadataProps = StaticMetadataProps & {
  /**
   * Optional click handler to open a dialog or side panel on click. Note that this MUST NOT navigate the page: use
   * `href` instead.
   */
  onClick: React.MouseEventHandler
}

type MetadataProps = LinkMetadataProps | ActionMetadataProps | StaticMetadataProps

export default function Metadata({children, className, ...props}: MetadataProps) {
  const id = useLabelId()
  const commonProps = {id, children, className}
  const interactiveProps = {...commonProps, inline: true}

  return 'href' in props ? (
    <Link href={props.href} {...interactiveProps} />
  ) : 'onClick' in props ? (
    <Link as="button" onClick={props.onClick} {...interactiveProps} />
  ) : (
    <span {...commonProps} />
  )
}
