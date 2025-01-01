import {useState} from 'react'
import {Autocomplete, Dialog, FormControl, Stack} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'
import styles from './VisualStudioMatchDialog.module.css'

export interface VisualStudioMatchDialogProps {
  errorMessage: string | null
  hasVssLicensesLeft: boolean
  isSaving: boolean
  isVolumeLicensed: boolean
  licenseeFullName: string
  licenseeLogin: string
  onClose: () => void
  onConfirm: () => void
  onDismissError: () => void
}

export function VisualStudioMatchDialog(props: VisualStudioMatchDialogProps) {
  const [selectedVsLogin, setSelectedVsLogin] = useState<{id: string; text: string} | null>(null)
  const [inputValue, setInputValue] = useState('')
  const [showVsLoginFieldError, setShowVsLoginFieldError] = useState(false)

  const selectedIds = selectedVsLogin ? [selectedVsLogin.id] : []

  // TODO: replace static data with actual API call
  const menuItems = [
    {text: 'alex@github.com', id: '1'},
    {text: 'alexjoe@github.com', id: '2'},
    {text: 'alextruss@github.com', id: '3'},
    {text: 'thalex@github.com', id: '4'},
    {text: 'foo@bar.com', id: '5'},
  ]

  // Temp filtering for correct match-any-part-of-the-string behavior; eventually this will be replaced with an API call
  const filterFn = (item: {text: string; id: string}) => {
    const lowerCaseInput = inputValue.toLowerCase()
    return item.text.toLowerCase().includes(lowerCaseInput)
  }

  return (
    <Dialog
      title="Change to Visual Studio license"
      subtitle={`You're about to convert this user's current${
        props.isVolumeLicensed ? '' : ' metered'
      } GitHub Enterprise license to a Visual Studio subscription.`}
      width="large"
      onClose={props.onClose}
      footerButtons={[
        {buttonType: 'default', content: 'Cancel', onClick: props.onClose},
        {
          buttonType: 'primary',
          content: 'Confirm change',
          disabled: !props.hasVssLicensesLeft || props.isSaving,
          onClick: () => {
            if (!selectedVsLogin) {
              setShowVsLoginFieldError(true)
              return
            }
            props.onConfirm()
          },
        },
      ]}
    >
      <Stack direction="vertical">
        {props.errorMessage && (
          <Banner variant="critical" title="Error saving license change" hideTitle onDismiss={props.onDismissError}>
            {props.errorMessage}
          </Banner>
        )}
        {!props.hasVssLicensesLeft && (
          <Banner variant="warning" title="No Visual Studio licenses available" hideTitle>
            You&apos;ve used up all your available Visual Studio licenses. To manage your licenses, visit your Visual
            Studio admin portal.
          </Banner>
        )}
        <Stack direction="horizontal" gap="normal">
          <Stack direction="vertical" gap="none" className={clsx(styles.vsDialogCol)}>
            <div className="f6 fgColor-muted text-semibold">Current:</div>
            <div className="f5 text-semibold">GitHub Enterprise</div>
            {!props.isVolumeLicensed && <div className="f6 fgColor-muted">Billed at $21/user per month</div>}
          </Stack>
          <Stack direction="vertical" gap="none" className={clsx(styles.vsDialogCol)}>
            <div className="f6 fgColor-muted text-semibold">New:</div>
            <div className="f5 text-semibold">Visual Studio subscription</div>
            {props.hasVssLicensesLeft ? (
              <div className="f6 fgColor-muted">Managed by your Visual Studio agreement</div>
            ) : (
              <div className="f6 fgColor-attention">0 licenses remaining</div>
            )}
          </Stack>
        </Stack>
        {props.hasVssLicensesLeft && (
          <Stack direction="vertical" gap="none">
            <FormControl>
              <FormControl.Label id="vs-login-email" required>
                Visual Studio login email
              </FormControl.Label>
              <Autocomplete>
                <Autocomplete.Input
                  block
                  value={inputValue}
                  onChange={e => {
                    setInputValue(e.target.value)
                    // typing clears any previous pick
                    setSelectedVsLogin(null)
                    setShowVsLoginFieldError(false)
                  }}
                  placeholder="Search by email or UPN"
                  aria-invalid={showVsLoginFieldError && !selectedVsLogin}
                  validationStatus={showVsLoginFieldError && !selectedVsLogin ? 'error' : undefined}
                />
                <Autocomplete.Overlay>
                  <Autocomplete.Menu
                    aria-labelledby="vs-login-email"
                    items={menuItems}
                    filterFn={filterFn}
                    selectedItemIds={selectedIds}
                    onSelectedChange={selected => {
                      // `selected` is always an array of selected items
                      const picked = Array.isArray(selected) ? selected[0] : undefined

                      if (!picked) return // nothing chosen

                      setSelectedVsLogin(picked)
                      setInputValue(picked.text)
                      setShowVsLoginFieldError(false)
                    }}
                  />
                </Autocomplete.Overlay>
              </Autocomplete>
              {showVsLoginFieldError && !selectedVsLogin && (
                <FormControl.Validation variant="error">
                  Please enter a valid email address or UPN (User Principal Name).
                </FormControl.Validation>
              )}
              <FormControl.Caption>
                Enter the login email address associated with a Visual Studio subscription associated with&nbsp;
                <span className="text-semibold">{props.licenseeFullName}</span> (
                <span className="text-semibold">{props.licenseeLogin}</span>).
              </FormControl.Caption>
            </FormControl>
          </Stack>
        )}
      </Stack>
    </Dialog>
  )
}
