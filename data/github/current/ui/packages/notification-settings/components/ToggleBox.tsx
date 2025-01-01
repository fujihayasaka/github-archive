import {useId, useState} from 'react'

import {Box, Heading, Text, ToggleSwitch, type BetterSystemStyleObject} from '@primer/react'

interface ToggleBoxProps {
  title: string
  subtitle: string
  checked: boolean
  sx?: BetterSystemStyleObject
  onChange?: (value: boolean) => void
}

function ToggleBox(props: ToggleBoxProps) {
  const labelId = useId()
  const descriptionId = useId()

  const [checked, setChecked] = useState<boolean>(props.checked || false)

  const onToggle = (value: boolean) => {
    setChecked(value)
    props.onChange?.(value)
  }

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        flexBasis: '100%',
        ...(props.sx ?? {}),
      }}
    >
      <Box sx={{display: 'flex', mt: 0, justifyContent: 'space-between'}}>
        <Heading as="h3" sx={{fontSize: 1, fontWeight: 'bold', m: 0}} id={labelId}>
          {props.title}
        </Heading>
      </Box>
      <Text as="p" sx={{color: 'fg.muted', mt: 0, mb: 2, flexGrow: 2}} id={descriptionId}>
        {props.subtitle}
      </Text>
      <ToggleSwitch
        checked={checked}
        size="small"
        statusLabelPosition="end"
        sx={{mr: 'auto'}}
        onClick={() => onToggle(!checked)}
        aria-labelledby={labelId}
        aria-describedby={descriptionId}
      />
    </Box>
  )
}

export default ToggleBox
