import {Box, Label, Text} from '@primer/react'

type ControlGroupBoxProps = {
  children: React.ReactNode
  title: string
  showGHASLabel: boolean
}

const ControlGroupBox = ({children, title, showGHASLabel}: ControlGroupBoxProps) => {
  const boxSx = {
    borderWidth: 1,
    borderStyle: 'solid',
    borderColor: 'border.muted',
    marginBottom: 4,
    borderRadius: 2,
  }
  const headerSx = {
    backgroundColor: 'canvas.subtle',
    borderBottomWidth: 1,
    borderBottomStyle: 'solid',
    borderBottomColor: 'border.muted',
    padding: 2,
    borderTopLeftRadius: 2,
    borderTopRightRadius: 2,
  }
  return (
    <Box sx={boxSx}>
      <Box sx={headerSx}>
        <Text as="strong" sx={{fontSize: 2}}>
          {title}
        </Text>{' '}
        {showGHASLabel && <Label>GitHub Advanced Security</Label>}
      </Box>

      {children}
    </Box>
  )
}

export default ControlGroupBox
