import styles from './LayoutHelpers.module.css'

export function wrapElement(
  wrappedElement: React.ReactNode,
  // In case of Timelinetem, this represent the avatar for an IssueComment event
  leadingElement?: React.ReactNode,
  key?: string,
) {
  return (
    <div
      className={`${styles.timelineElement} ${leadingElement ? '' : styles.nonLeadingElement}`}
      key={key}
      data-wrapper-timeline-id={key}
    >
      {leadingElement}
      {wrappedElement}
    </div>
  )
}
