import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {FormControl, TextInput} from '@primer/react'
import {forwardRef, useEffect} from 'react'

import {type CheckResult, isError} from '../hooks/use-check-name'
import type {WorkbenchRoutePayload} from '../types/workbench-types'

const repoInputAvailableMessageId = 'RepoNameInput-is-available'
const repoInputDefaultMessageId = 'RepoNameInput-message'

interface NameInputProps {
  sparkName: string
  disabled?: boolean
  hideBlankCheck?: boolean
  onChange: (newRepoName: string) => void
  onValidityChange: ({valid, invalidReason}: {valid: boolean; invalidReason?: string}) => void
  expandNameInput?: boolean
  result: CheckResult
  runCheck: (newName: {friendlyName: string}) => void
}

export const NameInput = forwardRef((props: NameInputProps, ref: React.ForwardedRef<HTMLInputElement>) => {
  const {sparkName, onChange, onValidityChange, expandNameInput, result, runCheck} = props

  useEffect(() => {
    let invalidReason = 'none'
    if (!sparkName) {
      invalidReason = 'empty'
    }

    onValidityChange({valid: false, invalidReason})
    runCheck({friendlyName: sparkName})
  }, [onValidityChange, runCheck, sparkName])

  return (
    <FormControl required disabled={props.disabled}>
      <FormControl.Label>Name</FormControl.Label>
      <TextInput
        block
        data-1p-ignore="true"
        ref={ref}
        name="name"
        className={expandNameInput ? 'width-full' : ''}
        value={sparkName}
        placeholder="Enter name"
        onChange={event => onChange(event.target.value)}
        validationStatus={isError(result) ? 'error' : undefined}
        aria-describedby={`${repoInputAvailableMessageId} ${repoInputDefaultMessageId}`}
      />
      <NameCheckValidation result={result} sparkName={sparkName} hideBlankCheck={props.hideBlankCheck} />
    </FormControl>
  )
})

NameInput.displayName = 'RepoNameInput'

interface NameCheckValidationProps {
  sparkName: string
  hideBlankCheck?: boolean
  result: CheckResult
}

function NameCheckValidation(props: NameCheckValidationProps) {
  const {sparkName, result} = props
  const {login} = useRoutePayload<WorkbenchRoutePayload>()

  if (!sparkName) {
    return props.hideBlankCheck ? null : (
      <FormControl.Validation id={repoInputDefaultMessageId} variant="error">
        New repository name must not be blank
      </FormControl.Validation>
    )
  }

  switch (result.status) {
    case 'none':
      return (
        // This component is a descendant of `FormControl`
        // eslint-disable-next-line primer-react/direct-slot-children
        <FormControl.Caption>
          <span aria-live="polite">Checking availability…</span>
        </FormControl.Caption>
      )
    case 'not_found':
      return (
        <FormControl.Validation id={repoInputDefaultMessageId} variant="error">
          Not Found
        </FormControl.Validation>
      )
    case 'error':
      return result.generatedName ? (
        <FormControl.Validation id={repoInputDefaultMessageId} variant="error">
          The spark <strong>{result.generatedName}</strong> {result.errors}.
        </FormControl.Validation>
      ) : (
        // An error without repo is not coming from the server, it's likely a fetch error
        <FormControl.Validation id={repoInputDefaultMessageId} variant="error">
          {"Couldn't check availability"}
        </FormControl.Validation>
      )
    case 'reworded':
    case 'ok':
      return (
        // eslint-disable-next-line primer-react/direct-slot-children
        <FormControl.Caption>
          Your spark will be published as{' '}
          <strong>
            {result.generatedName}--{login}.github.app
          </strong>
          .
        </FormControl.Caption>
      )
  }
}
