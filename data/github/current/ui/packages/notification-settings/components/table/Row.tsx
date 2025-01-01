import type React from 'react'
import {useId} from 'react'

import {Box, Heading, Text, type BetterSystemStyleObject} from '@primer/react'
import type {ActionProps} from '../ActionProps'

export interface RowProps {
  title: string
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  subtitle?: React.ComponentElement<any, any> | string
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  renderAction?: <T extends ActionProps>(props: Required<ActionProps>) => React.ComponentElement<T, any>
  separator?: boolean
  sx?: BetterSystemStyleObject
}

function Row(props: RowProps) {
  const labelId = useId()
  const descriptionId = useId()
  const actionId = useId()

  return (
    <Box
      sx={{
        display: 'flex',
        py: 3,
        mx: 3,
        borderColor: 'border.default',
        borderBottomWidth: props.separator === false ? 0 : 1,
        borderBottomStyle: 'solid',
        ...props.sx,
      }}
    >
      <div className={`mr-sm-0 ml-sm-0`}>
        <Heading as="h3" sx={{fontSize: 1, mb: 0}} id={labelId}>
          {props.title}
        </Heading>
        <Text sx={{color: 'fg.muted', m: 0}} id={descriptionId}>
          {props.subtitle}
        </Text>
        {props.renderAction && (
          <Box
            sx={{
              display: 'flex',
              flexDirection: 'row',
              gap: 2,
              alignItems: 'flex-start',
              justifyContent: 'space-between',
              mt: 2,
              mb: 1,
            }}
          >
            {props.renderAction({
              id: actionId,
              'aria-labelledby': `${labelId} ${actionId}`,
              'aria-describedby': descriptionId,
            })}
          </Box>
        )}
      </div>
    </Box>
  )
}

export default Row
