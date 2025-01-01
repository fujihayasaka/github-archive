import {FocusKeys} from '@primer/behaviors'
import {useFocusZone} from '@primer/react'
import {useRef} from 'react'

type Labelled = {'aria-label': string} | {'aria-labelledby': string}
type DivProps = React.HTMLAttributes<HTMLDivElement>
type ToolbarProps = Omit<DivProps, 'role'> & Labelled

export function Toolbar(props: ToolbarProps) {
  const {className, ...restProps} = props
  const containerRef = useRef<HTMLDivElement>(null)
  useFocusZone({
    containerRef,
    focusInStrategy: 'first',
    focusOutBehavior: 'stop',
    bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.HomeAndEnd,
  })

  return (
    <div ref={containerRef} className={className} role="toolbar" {...restProps}>
      {props.children}
    </div>
  )
}
