import {Link, Token, type TokenProps, type BetterSystemStyleObject} from '@primer/react'
import {useEffect, useRef, useState} from 'react'
import styles from './IssueTypeToken.module.css'
import {Tooltip} from '@primer/react/next'

export type IssueTypeTokenProps = {
  name: string
  color: string
  href: string
  getTooltipText: (isTextTruncated: boolean) => string | undefined
  sx?: BetterSystemStyleObject
} & Pick<TokenProps, 'size'>

export const IssueTypeToken = ({name, color, href, getTooltipText, size, sx}: IssueTypeTokenProps) => {
  const tokenRef = useRef<HTMLElement>(null)
  const [truncated, setTruncated] = useState(false)

  useEffect(() => setTruncated(isTextTruncated(tokenRef.current)), [setTruncated, tokenRef])

  const internal = (
    <Link href={href}>
      <Token
        className={styles.token}
        data-color={color}
        ref={tokenRef}
        sx={sx}
        // the span in the text is allowing us to check if the text is truncated
        text={<span className={styles.tokenText}>{name}</span>}
      />
    </Link>
  )

  const tooltipText = getTooltipText(truncated)

  return (
    <div className={styles.container} data-size={size}>
      {tooltipText ? <Tooltip text={tooltipText}>{internal}</Tooltip> : internal}
    </div>
  )
}
// This is not bullet proof, since the true inner width of the element is rounded down.
// I think it's pretty good though. See discussion here https://stackoverflow.com/questions/64689074/how-to-check-if-text-is-truncated-by-css-using-javascript
const isTextTruncated = (e: HTMLElement | null): boolean => {
  if (!e || !e.firstElementChild) return false
  return e.firstElementChild.scrollWidth > e.firstElementChild.clientWidth
}
