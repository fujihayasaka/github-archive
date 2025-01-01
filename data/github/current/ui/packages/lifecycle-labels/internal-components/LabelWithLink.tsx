import {Stack} from '@primer/react/experimental'

interface LabelWithLinkProps {
  label: React.ReactNode
  link?: React.ReactNode
  className?: string
}

/** Render a `Label` with an optional link adjacent. */
export const LabelWithLink = ({label, link, className}: LabelWithLinkProps) => {
  if (link) {
    return (
      <Stack direction="horizontal" gap="condensed" align="baseline" className={className}>
        {label} {link}
      </Stack>
    )
  }
  if (className) return <span className={className}>{label}</span>
  return <>{label}</>
}
