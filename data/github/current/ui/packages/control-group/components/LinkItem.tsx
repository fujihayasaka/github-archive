import {ChevronRightIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {useSlots} from '@primer/react/experimental'
import Title from './Title'
import Description from './Description'
import styled from 'styled-components'
import itemStyles from './Item.module.css'
import {clsx} from 'clsx'
import styles from './LinkItem.module.css'
import type {CSSProperties} from 'react'

const slotConfig = {
  title: Title,
  description: Description,
}

export type ControlGroupLinkProps = {
  href: string
  children: React.ReactNode
  leadingIcon?: React.ReactNode
  nestedLevel?: 0 | 1 | 2
  value?: string
}

// Using inclusive component styles for the link (https://inclusive-components.design/cards/)
// For now we'll hold off on converting this to CSS modules until issues with overrides are resolved (https://github.com/github/react-lang/issues/182)
const StyledLink = styled(Link)`
  text-decoration: none;
  color: inherit;
  :hover {
    text-decoration: none;
  }
  ::after {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    top: 0;
    content: '';
  }
  :focus {
    text-decoration: underline;
    outline: none;
  }
`

const LinkItem = ({children, leadingIcon = null, href, value, nestedLevel = 0}: ControlGroupLinkProps) => {
  const [slots] = useSlots(children, slotConfig)
  const {title, description} = slots

  return (
    <div
      className={clsx(itemStyles.container, styles.container)}
      style={{'--nested-level': nestedLevel} as CSSProperties}
    >
      <div className={itemStyles.contents}>
        {leadingIcon ? (
          <div className={itemStyles.leadingVisual}>
            <div className={styles.leadingIcon}>{leadingIcon}</div>
          </div>
        ) : null}

        <StyledLink href={href} className={itemStyles.title}>
          {title}
        </StyledLink>

        <div className={clsx('descriptionBox', itemStyles.description)}>{description}</div>

        <div className={itemStyles.trailingVisual}>
          <div className={styles.linkIndicator}>
            {value && <span>{value}</span>}
            <ChevronRightIcon />
          </div>
        </div>
      </div>
    </div>
  )
}

export default LinkItem
