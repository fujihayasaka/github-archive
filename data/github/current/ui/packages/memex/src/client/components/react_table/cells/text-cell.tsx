import {Text, type TextProps} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef} from 'react'

import {SanitizedHtml} from '../../dom/sanitized-html'
// eslint-disable-next-line primer-react/enforce-css-module-default-import
import styles0 from './text-cell.module.css'

export const TextCell = forwardRef<
  HTMLElement,
  TextProps & {dangerousHtml?: string; isDisabled?: boolean; className?: string}
>(({children, dangerousHtml, sx, className, ...rest}, ref) => {
  if (dangerousHtml) {
    return (
      <SanitizedHtml {...rest} ref={ref} sx={sx} className={clsx(className, styles0.SanitizedHtml)}>
        {dangerousHtml}
      </SanitizedHtml>
    )
  }

  return (
    <Text {...rest} ref={ref} sx={sx} className={clsx(className, styles0.SanitizedHtml)}>
      {children}
    </Text>
  )
})

TextCell.displayName = 'TextCell'
