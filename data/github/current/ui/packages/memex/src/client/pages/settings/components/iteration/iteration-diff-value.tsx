import {testIdProps} from '@github-ui/test-id-props'
import {type SxProp, Text} from '@primer/react'
import type {ReactNode} from 'react'

import {identity} from '../../../../../utils/identity'
import styles from './iteration-diff-value.module.css'

type DiffValueProps = {
  originalValue?: string
  /** Custom render function for the original value. */
  renderOriginalValue?: (value: string) => ReactNode
  updatedValue?: string
  /** Custom render function for the updated value. */
  renderUpdatedValue?: (value: string) => ReactNode
  testId?: string
} & SxProp

export const DiffValue = ({
  originalValue = '',
  updatedValue = '',
  renderUpdatedValue = identity,
  renderOriginalValue = identity,
  sx,
  testId,
}: DiffValueProps) => {
  return (
    <Text
      sx={{
        ...(sx ?? {}),
      }}
      className={styles.Text}
      {...(testId ? testIdProps(testId) : {})}
    >
      {originalValue === updatedValue ? (
        <span>{renderUpdatedValue(updatedValue)}</span>
      ) : (
        <>
          {originalValue && (
            <del className={styles.Text_1} {...testIdProps('original-value')}>
              {renderOriginalValue(originalValue)}
            </del>
          )}
          {originalValue && updatedValue && <span className={styles.Text}> </span>}
          {updatedValue && (
            <ins className={styles.Text_2} {...testIdProps('updated-value')}>
              {renderUpdatedValue(updatedValue)}
            </ins>
          )}
        </>
      )}
    </Text>
  )
}
