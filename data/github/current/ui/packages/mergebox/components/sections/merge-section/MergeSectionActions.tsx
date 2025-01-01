import type {PropsWithChildren, ReactElement} from 'react'
import React, {Children, cloneElement} from 'react'
import {ButtonWithDropdown} from '../common/ButtonWithDropdown'
import {Button} from '@primer/react'

/**
 *
 * Formats the actions in the merge section
 * Standardizes the space between different slots
 * At small viewport sizes and below, wraps the second slot beneath the first slot and makes any buttons fill the full available width
 */
export function MergeSectionActions({children, className}: PropsWithChildren<{className?: string}>) {
  return (
    <div className={`d-flex flex-items-start flex-sm-items-center flex-column flex-sm-row gap-2 ${className}`}>
      {children}
    </div>
  )
}

/**
 * The child can be any single valid React element
 * For Button or ButtonWithDropdown elements, it will apply the correct class to ensure the button fills the full width at small viewport sizes and below
 */
MergeSectionActions.Slot = function MergeSectionsActionsSlot({children}: PropsWithChildren) {
  // eslint-disable-next-line @eslint-react/no-children-only
  let element = Children.only(children)

  if (React.isValidElement(element)) {
    element = applyStretchStyleToChild(element)
  }

  return element
}

function applyStretchStyleToChild(element: ReactElement) {
  if (element.type === ButtonWithDropdown || element.type === Button) {
    // eslint-disable-next-line @eslint-react/no-clone-element
    return cloneElement(element, {
      className: `flex-self-stretch flex-shrink-0 ${element.props.className}`,
    })
  }
  return element
}
