import {testIdProps} from '@github-ui/test-id-props'
import {Box, Label} from '@primer/react'

import styles from './add-break-button.module.css'

interface AddBreakButtonProps {
  onClick: () => void
  /**
   * The hover target of the first Insert Break button can interfere with the
   * click target of buttons in the header (like `Add Iteration`), so this component
   * provides a way to turn that padding into a margin for that button.
   * */
  removeTopPadding: boolean
}

/**
 * Button to insert a break between two iterations. Intended to be placed directly between
 * iteration rows in the table.
 */
export function AddBreakButton({onClick, removeTopPadding}: AddBreakButtonProps) {
  return (
    <div className={styles.Box}>
      <Box
        sx={{
          pt: removeTopPadding ? 0 : undefined,
          mt: removeTopPadding ? 3 : undefined,
        }}
        className={styles.Box_1}
      >
        <Label
          onClick={onClick}
          as="button"
          type="button"
          className={styles.Label}
          {...testIdProps('add-break-button')}
        >
          Insert break
        </Label>
      </Box>
    </div>
  )
}
