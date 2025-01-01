import {Box, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {AlertIcon} from '@primer/octicons-react'

export type BranchNextStepFlashesProps = {
  errorMessages: string[]
}

export const BranchNextStepFlashes = ({errorMessages}: BranchNextStepFlashesProps) => {
  if (errorMessages.length === 0) {
    return null
  }

  return (
    <Box sx={{mb: 2}}>
      {errorMessages.map((errorMessage, index) => (
        <Flash key={`${errorMessage}-${String(index)}`} variant="warning">
          <Octicon icon={AlertIcon} />
          <span>{errorMessage}</span>
        </Flash>
      ))}
    </Box>
  )
}
