import {AlertFillIcon} from '@primer/octicons-react'
import {Box, Link, Text, type BetterSystemStyleObject} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

export interface ErrorWithRetryProps {
  message: string
  retry: () => void
  sx?: BetterSystemStyleObject
}

export function ErrorWithRetry({message, retry, sx}: ErrorWithRetryProps) {
  return (
    <Box sx={{display: 'flex', alignItems: 'center', gap: 1, ...sx}}>
      <div>
        <Octicon icon={AlertFillIcon} sx={{color: 'attention.fg'}} className="mr-1" />
        <Text sx={{fontSize: 0, color: 'fg.muted'}}>{message}</Text>
      </div>
      <Link as="button" underline onClick={retry} sx={{fontSize: 0}}>
        <Text sx={{fontSize: 0}}>Try again</Text>
      </Link>
    </Box>
  )
}
