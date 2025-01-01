import {useState, type ComponentProps} from 'react'
import {Button as PrimerButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'

// Wraps the Primer Button component.
// If the button is inactive, then onClick does nothing.
export function Button(props: ComponentProps<typeof PrimerButton>) {
  return (
    <PrimerButton
      {...props}
      onClick={e => {
        if (props.inactive) return
        props.onClick?.(e)
      }}
    />
  )
}

// Wraps the Primer Banner component.
// Automatically hides the banner on dismiss
// without needing to manually setup your own state.
export function DismissibleBanner(props: ComponentProps<typeof Banner>) {
  const [visible, setVisible] = useState(true)
  return (
    visible && (
      <Banner
        {...props}
        onDismiss={() => {
          props.onDismiss?.()
          setVisible(false)
        }}
      />
    )
  )
}
