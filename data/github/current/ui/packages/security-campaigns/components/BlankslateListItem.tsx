import type {ReactNode} from 'react'
import {Blankslate, type BlankslateProps} from '@primer/react/experimental'

export type BlankslateListItemProps = BlankslateProps & {
  children: ReactNode
}

export function BlankslateListItem({children, ...props}: BlankslateListItemProps): JSX.Element {
  // A ListView is a <ul> element, so it only accepts <li> children. This component is a workaround to allow
  // Blankslate to be used as a child of a ListView. We don't need to add any additional styles to the <li> element
  // because the ListView already ensures that the <li> element is styled correctly.
  return (
    <li>
      <Blankslate {...props}>{children}</Blankslate>
    </li>
  )
}
