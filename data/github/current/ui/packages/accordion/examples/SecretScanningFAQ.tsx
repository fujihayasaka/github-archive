import {useState} from 'react'
import {Heading, Link, Stack, Text} from '@primer/react'
import styles from './SecretScanningFAQ.module.css'
import {Accordion} from '../Accordion'
import {LinkExternalIcon} from '@primer/octicons-react'

export default function DefaultExample() {
  const [expandedItems, setExpandedItems] = useState<string[]>([])

  return (
    <Stack gap="condensed">
      <Heading as="h2" variant="medium">
        Frequently asked questions
      </Heading>
      <Accordion expandedItems={expandedItems} onChange={setExpandedItems}>
        <Accordion.Item value="section-1">
          <Accordion.Trigger>
            <h3 className={styles.heading}>What happens once I start the scan?</h3>
          </Accordion.Trigger>
          <Accordion.Content className={styles.content}>
            <Text size="medium">
              GitHub will perform a point-in-time scan of all repositories in your organization, reporting back helpful
              insights like count of secrets leaked per type. No specific secrets will be stored or shared.
            </Text>
          </Accordion.Content>
        </Accordion.Item>
        <Accordion.Item value="section-2">
          <Accordion.Trigger>
            <h3 className={styles.heading}>How will I be notified?</h3>
          </Accordion.Trigger>
          <Accordion.Content className={styles.content}>
            <Text size="medium">
              GitHub will notify you via email when the report is complete. If you’ve previously opted in to marketing
              or sales-based communication from GitHub, you may receive additional content about the report. You can
              opt-out at any time from your{' '}
              <Link href="#" inline>
                email settings.
              </Link>
            </Text>
          </Accordion.Content>
        </Accordion.Item>
        <Accordion.Item value="section-3">
          <Accordion.Trigger>
            <h3 className={styles.heading}>What is the cost of a leaked secret?</h3>
          </Accordion.Trigger>
          <Accordion.Content className={styles.content}>
            <Text size="medium">
              A single exposed secret can lead to a comprehensive breach, potentially costing millions in addition to
              untold damage to an organization&apos;s reputation. &nbsp;
            </Text>
            <Link href="#">
              View the ROI calculator <LinkExternalIcon />
            </Link>
          </Accordion.Content>
        </Accordion.Item>
      </Accordion>
    </Stack>
  )
}
