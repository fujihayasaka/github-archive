import {Box, Text} from '@primer/react-brand'

import styles from './DevHelpText.module.css'

interface DevHelpTextProps {
  verificationToken: number | null
}

export const DevHelpText = ({verificationToken}: DevHelpTextProps): JSX.Element => {
  return (
    <Box paddingBlockStart="condensed">
      <Text as="p" size="100" variant="muted">
        Psst, Hubber:
      </Text>
      {verificationToken ? (
        <Text as="p" size="100" variant="muted">
          In local development, you can use this launch code to verify your email:{' '}
          <span className={styles.token}>{verificationToken}</span>
        </Text>
      ) : (
        <Text as="p" size="100" variant="muted">
          If you wait a second and reload this page, you should see the launch code to verify your email address in
          local development.
        </Text>
      )}
    </Box>
  )
}
