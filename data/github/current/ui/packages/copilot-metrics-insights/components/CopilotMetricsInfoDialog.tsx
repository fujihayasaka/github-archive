import {InfoIcon, QuestionIcon} from '@primer/octicons-react'
import {AnchoredOverlay, Heading, IconButton, Link, Text} from '@primer/react'
import {clsx} from 'clsx'
import {useState} from 'react'
import styles from './CopilotMetricsInfoDialog.module.css'

interface CopilotMetricsInfoDialogProps {
  dialogHeader: string
  dialogText: string
  helpLinks?: HelpLink[]
}

export type DialogInfo = {
  text: string
  helpLinks?: HelpLink[]
}

export type HelpLink = {
  text: string
  url: string
}

const CopilotMetricsInfoDialog = (props: CopilotMetricsInfoDialogProps) => {
  const [open, setOpen] = useState(false)
  const {dialogHeader, dialogText, helpLinks} = props

  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => setOpen(false)}
      align="center"
      renderAnchor={anchorProps => {
        const {'aria-labelledby': _, ...otherAnchorProps} = anchorProps
        return (
          // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
          <IconButton
            {...otherAnchorProps}
            icon={InfoIcon}
            variant="invisible"
            aria-label="How to read this metric"
            unsafeDisableTooltip
            data-testid="copilot-metrics-info-button"
            className="ml-2"
          />
        )
      }}
    >
      <div className={clsx(styles.CopilotMetricsInfoDialog)} data-testid="copilot-metrics-info-dialog">
        <Heading as="h4" className={clsx(styles.CopilotMetricsInfoDialogHeader)}>
          {dialogHeader}
        </Heading>

        <Text size="medium" as="div" className={styles.CopilotMetricsInfoDialogText}>
          {dialogText}
        </Text>

        {helpLinks?.map(link => (
          <Link href={link.url} target="_blank" as="a" key={link.url} className={styles.CopilotMetricsInfoDialogLink}>
            <QuestionIcon />
            <p className="ml-2">{link.text}</p>
          </Link>
        ))}
      </div>
    </AnchoredOverlay>
  )
}

export default CopilotMetricsInfoDialog
