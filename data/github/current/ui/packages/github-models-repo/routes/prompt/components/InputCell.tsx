import {Stack} from '@primer/react'
import {clsx} from 'clsx'
import {Fragment, type PropsWithChildren} from 'react'
import type {CompareRow} from '../types'
import {VariableInput} from '../variables'
import styles from './InputCell.module.css'

interface InputCellProps extends PropsWithChildren {
  row: CompareRow
  skipped?: boolean
  variables?: string[]
}

export function InputCell({children, row, skipped, variables}: InputCellProps) {
  // If variables array is provided, render all variables in a nested structure
  if (variables && variables.length > 0) {
    return (
      <Stack
        gap={{narrow: 'condensed', regular: 'normal'}}
        direction={{narrow: 'vertical', regular: 'horizontal'}}
        className={styles.inputCell}
      >
        <Stack.Item grow className={clsx({'fgColor-muted': skipped})}>
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'max-content 1fr',
              gap: 'var(--base-size-8)',
              rowGap: 'var(--base-size-4)',
            }}
          >
            {variables.map(variableKey => {
              const input = row?.data?.[variableKey]?.trim()
              const hasInput = Boolean(input)

              return (
                <Fragment key={variableKey}>
                  <div key={`${variableKey}-label`} className="color-fg-subtle">
                    {variableKey}:
                  </div>
                  <div key={`${variableKey}-value`} className={clsx({'fgColor-muted': !hasInput})}>
                    {input || `Add ${variableKey} text`}
                  </div>
                </Fragment>
              )
            })}
          </div>
        </Stack.Item>

        <div className={styles.actionWrapper}>{children}</div>
      </Stack>
    )
  }

  // Fallback to default behavior when no variables specified
  const input = row?.data?.[VariableInput]?.trim()
  const hasInput = Boolean(input)

  return (
    <Stack
      gap={{narrow: 'condensed', regular: 'normal'}}
      direction={{narrow: 'vertical', regular: 'horizontal'}}
      className={styles.inputCell}
    >
      <Stack.Item grow className={clsx({'fgColor-muted': skipped || !hasInput})}>
        {input || `Add ${VariableInput} text`}
      </Stack.Item>

      <div className={styles.actionWrapper}>{children}</div>
    </Stack>
  )
}
