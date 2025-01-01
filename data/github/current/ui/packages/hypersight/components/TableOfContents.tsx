import {memo} from 'react'
import {useHeadings, type Heading} from '../utils/HeadingContext'
import {useActiveSection} from '../utils/use-active-section'
import {NavList} from '@primer/react'
import styles from './TableOfContents.module.css'

const HeadingLink = memo(function HeadingLink({
  heading,
  activeId,
  innerClassName,
}: {
  innerClassName?: string
  heading: Heading
  activeId: string | null
}) {
  return (
    <NavList.Item
      href={`#${heading.id}`}
      aria-current={activeId === heading.id ? 'location' : undefined}
      onClick={e => {
        e.preventDefault()
        document.getElementById(heading.id)?.scrollIntoView({
          behavior: 'smooth',
        })
      }}
    >
      <span className={innerClassName}>{heading.text}</span>
    </NavList.Item>
  )
})

export default function TableOfContents({className}: {className?: string}) {
  const {headings, organizedHeadings} = useHeadings()
  const activeId = useActiveSection(headings.map(h => h.id))

  return (
    <div className={styles.tocContainer}>
      <h2 className={styles.textSubtitle}>Outline</h2>
      <NavList aria-label="Table of contents" className={className}>
        {Object.values(organizedHeadings).map(({h2, children}) => (
          <div key={h2.id}>
            <HeadingLink heading={h2} activeId={activeId} />
            {children.map(h3 => (
              <HeadingLink key={h3.id} heading={h3} activeId={activeId} innerClassName={styles.nestedNavItem} />
            ))}
          </div>
        ))}
      </NavList>
    </div>
  )
}
