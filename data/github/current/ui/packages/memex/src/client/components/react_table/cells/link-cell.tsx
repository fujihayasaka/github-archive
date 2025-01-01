import {Link, type LinkProps, useRefObjectAsForwardedRef} from '@primer/react'
import {forwardRef, useRef} from 'react'

import styles from './link-cell.module.css'

export const LinkCell = forwardRef<HTMLAnchorElement, LinkProps & {dangerousHtml?: string; isDisabled?: boolean}>(
  (props, forwardedRef) => {
    const ref = useRef<HTMLAnchorElement>(null)
    useRefObjectAsForwardedRef(forwardedRef, ref)
    const sx = props.isDisabled ? {color: 'fg.muted', ...props.sx} : props.sx
    return <Link target="_blank" rel="noreferrer" tabIndex={-1} {...props} sx={sx} ref={ref} className={styles.Link} />
  },
)

LinkCell.displayName = 'LinkCell'
