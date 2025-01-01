import {forwardRef, type Ref} from 'react'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {FormControl, Box, TextInput} from '@primer/react'

export const NewBranchName = forwardRef(function NewBranchName(
  {
    newBranchName,
    setNewBranchName,
  }: {
    newBranchName: string
    setNewBranchName: (newName: string) => void
  },
  ref?: Ref<HTMLInputElement>,
) {
  return (
    <FormControl>
      <FormControl.Label>New branch name</FormControl.Label>
      <Box sx={{display: 'flex', width: '100%'}}>
        <TextInput
          block
          className="color-bg-subtle"
          sx={{borderBottomRightRadius: 0, borderTopRightRadius: 0, width: '88%'}}
          value={newBranchName}
          onChange={e => setNewBranchName(e.target.value)}
          ref={ref}
        />
        <Box
          className="color-bg-subtle"
          sx={{
            display: 'flex',
            justifyContent: 'center',
            borderRightWidth: 1,
            borderLeftWidth: 0,
            borderTopWidth: 1,
            borderBottomWidth: 1,
            borderTopRightRadius: '10%',
            borderBottomRightRadius: '10%',
            borderColor: 'border.default',
            borderStyle: 'solid',
            width: '12%',
          }}
        >
          <CopyToClipboardButton
            tooltipProps={{direction: 'nw'}}
            textToCopy={newBranchName}
            ariaLabel="Copy to clipboard"
            className="pt-1"
            sx={{height: 25, width: 25}}
          />
        </Box>
      </Box>
    </FormControl>
  )
})
