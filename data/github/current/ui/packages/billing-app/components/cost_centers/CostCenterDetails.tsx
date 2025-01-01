import {Box, Heading, TextInput, FormControl} from '@primer/react'

import {Fonts, Spacing} from '../../utils/style'

interface Props {
  name: string
  setCostCenterName: (name: string) => void
}

export function CostCenterDetails({name, setCostCenterName}: Props) {
  return (
    <Box sx={{mb: Spacing.CardMargin}}>
      <Box sx={{mb: 2}}>
        <Heading as="h3" className="h2-override-shared-component" sx={{fontSize: Fonts.SectionHeadingFontSize}}>
          Cost center name
        </Heading>
        <span>Pick something memorable that will help when searching for this cost center.</span>
      </Box>

      <FormControl required>
        <FormControl.Label visuallyHidden>Cost Center Name Input</FormControl.Label>
        <TextInput
          block
          type="text"
          data-testid="cost-center-name-input"
          placeholder=""
          value={name}
          maxLength={255}
          onChange={e => setCostCenterName(e.target.value)}
        />
      </FormControl>
    </Box>
  )
}
