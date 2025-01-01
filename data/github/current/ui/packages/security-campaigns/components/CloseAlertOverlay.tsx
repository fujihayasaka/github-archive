import {useState} from 'react'
import pluralize from 'pluralize'
import {number as formatNumber} from '@github-ui/formatters'
import {Button, CounterLabel, Flash, FormControl, Radio, RadioGroup, Stack, Textarea} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {SyncIcon} from '@primer/octicons-react'
import {useCloseAlertsMutation} from '../hooks/use-close-alerts-mutation'
import {securityCampaignRepoCloseAlertsPath} from '@github-ui/paths'
import type {Repository} from '../types/repository'

export interface CloseAlertOverlayProps {
  setOpen: (open: boolean) => void
  repository: Repository
  securityCampaignNumber: number
  alertNumbers: number[]
  delegatedAlertDismissalEnabled: boolean
}

export const ResolutionType = {
  FalsePositive: 'false_positive',
  UsedInTests: 'used_in_tests',
  WontFix: 'wont_fix',
} as const

export type ResolutionType = (typeof ResolutionType)[keyof typeof ResolutionType]

export function CloseAlertOverlay(props: CloseAlertOverlayProps) {
  const {setOpen, repository, securityCampaignNumber, alertNumbers, delegatedAlertDismissalEnabled} = props

  const [selectedCloseReason, setSelectedCloseReason] = useState('')
  const [dismissalComment, setDismissalComment] = useState('')

  const [commentValidationError, setCommentValidationError] = useState(false)

  const validDismissalComment = delegatedAlertDismissalEnabled ? !!dismissalComment.trim() : true
  const isValid = !!selectedCloseReason && validDismissalComment

  const handleRadioGroupChange = (value: string | null) => {
    setSelectedCloseReason(value ?? '')
  }

  const {mutate, isPending, error} = useCloseAlertsMutation(
    securityCampaignRepoCloseAlertsPath({
      owner: repository.ownerLogin,
      repo: repository.name,
      securityCampaignNumber,
    }),
  )

  const onCloseAlerts = async () => {
    if (selectedCloseReason.trim() === '' && delegatedAlertDismissalEnabled) {
      setCommentValidationError(true)
      return
    } else {
      setCommentValidationError(false)
    }

    mutate(
      {
        alertNumbers,
        resolution: selectedCloseReason,
        dismissalComment,
      },
      {
        onSuccess: () => {
          setOpen(false)
          // Need to do a full page reload so that the sidebar numbers (which are not in react) get updated
          window.location.reload()
        },
      },
    )
  }

  return (
    <Dialog
      width="large"
      height="auto"
      onClose={() => setOpen(false)}
      title="Select a reason to close these alerts"
      renderFooter={() => (
        <Dialog.Footer>
          <Button onClick={() => setOpen(false)}>Cancel</Button>
          <Button
            variant="primary"
            onClick={onCloseAlerts}
            disabled={!isValid || isPending}
            leadingVisual={isPending ? SyncIcon : null}
          >
            Close {pluralize('alert', alertNumbers.length)}
            <CounterLabel scheme="primary" sx={{ml: 2}}>
              {formatNumber(alertNumbers.length)}
            </CounterLabel>
          </Button>
        </Dialog.Footer>
      )}
    >
      <Stack gap="normal">
        {error && <Flash variant="danger">{error.message}</Flash>}
        <RadioGroup name="alertCloseReasonGroup" onChange={handleRadioGroupChange} disabled={isPending}>
          <RadioGroup.Label visuallyHidden>Close reason</RadioGroup.Label>
          <FormControl>
            <Radio value={ResolutionType.FalsePositive} name="resolution" />
            <FormControl.Label>False positive</FormControl.Label>
            <FormControl.Caption>These alerts are not accurate or there is no actual threat</FormControl.Caption>
          </FormControl>
          <FormControl>
            <Radio value={ResolutionType.UsedInTests} name="resolution" />
            <FormControl.Label>Used in tests</FormControl.Label>
            <FormControl.Caption>These alerts are not in production code</FormControl.Caption>
          </FormControl>
          <FormControl>
            <Radio value={ResolutionType.WontFix} name="resolution" />
            <FormControl.Label>Won&apos;t fix</FormControl.Label>
            <FormControl.Caption>
              While the alerts are accurate, there are other factors not to fix them
            </FormControl.Caption>
          </FormControl>
        </RadioGroup>
        <div>
          <FormControl disabled={isPending}>
            <FormControl.Label required={delegatedAlertDismissalEnabled}>Comment</FormControl.Label>
            <Textarea
              sx={{width: '100%', display: 'block'}}
              placeholder="Let the security manager's team know why are you closing these alerts"
              rows={5}
              maxLength={280}
              name="dimissal_comment"
              onChange={e => setDismissalComment(e.target.value)}
            />
            {commentValidationError && (
              <FormControl.Validation variant="error">This field is required</FormControl.Validation>
            )}
          </FormControl>
        </div>
      </Stack>
    </Dialog>
  )
}
