import {FormControl, Checkbox, CheckboxGroup, Box} from '@primer/react'

type TypePrivateProps = {
  disabled?: boolean
  isPrivate: boolean
  setIsPrivate: (value: React.SetStateAction<boolean>) => void
  error?: string
}

export const TypePrivate = ({disabled = false, isPrivate, setIsPrivate, error}: TypePrivateProps) => (
  <Box sx={{mb: 3}}>
    <CheckboxGroup>
      <CheckboxGroup.Label visuallyHidden>Privacy setting</CheckboxGroup.Label>
      <FormControl disabled={disabled}>
        <Checkbox
          validationStatus={error ? 'error' : undefined}
          checked={isPrivate}
          data-testid="private-issue-type"
          onChange={() => setIsPrivate(prevIsPrivate => !prevIsPrivate)}
        />
        <FormControl.Label>Private repositories only</FormControl.Label>
        <FormControl.Caption>
          Prevents this issue type from being assigned to issues created in public repositories
        </FormControl.Caption>
      </FormControl>
      {error && <CheckboxGroup.Validation variant="error">{error}</CheckboxGroup.Validation>}
    </CheckboxGroup>
  </Box>
)
