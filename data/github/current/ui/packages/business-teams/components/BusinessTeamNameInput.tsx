import {FormControl, TextInput} from '@primer/react'
import {useEffect, useRef, useState, type ChangeEvent} from 'react'

import {type CheckResult, isError, useCheckBusinessTeamsName} from '../hooks/check-team-name'

const businessTeamNameInputAvailableMessageId = 'BusinessTeamName-is-available'
const businessTeamNameInputDefaultMessageId = 'BusinessTeamName-message'

export function BusinessTeamNameInput({
  businessTeamName,
  businessTeamSlug,
  readonly,
  hideBlankCheck,
  businessSlug,
  onChange,
  onValidityChange,
  editMode,
  maxTeamNameLength,
}: {
  businessTeamName: string
  businessTeamSlug?: string
  readonly?: boolean
  hideBlankCheck?: boolean
  businessSlug: string
  onChange: (newbusinessTeamName: string) => void
  onValidityChange: (valid: boolean) => void
  editMode?: boolean
  maxTeamNameLength: number
}) {
  const [result, runCheck] = useCheckBusinessTeamsName(onValidityChange)
  const [hasTeamName, setHasTeamName] = useState(false)
  const validateBTName = (event: ChangeEvent<HTMLInputElement>) => {
    const newTeamName = event.target.value
    onValidityChange(false)
    if (newTeamName) {
      runCheck({name: newTeamName, businessSlug, teamSlug: businessTeamSlug})
    }
    onChange(newTeamName)
    setHasTeamName(true)
  }

  const firstRender = useRef(true)
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false
      return
    }
  }, [firstRender, editMode])

  return (
    <FormControl id="business-team-name" required>
      <FormControl.Label>Name</FormControl.Label>
      <TextInput
        data-testid="business-team-name-input"
        value={businessTeamName}
        placeholder="Team Name"
        onChange={validateBTName}
        readOnly={readonly}
        validationStatus={isError(result) ? 'error' : undefined}
        aria-describedby={`${businessTeamNameInputAvailableMessageId} ${businessTeamNameInputDefaultMessageId}`}
        sx={{width: '100%', maxWidth: ['100%', null, null, '300px']}}
        trailingVisual={
          <span
            data-testid="business-team-name-input-counter"
            style={{
              fontSize: 'var(--text-body-size-small)',
            }}
          >
            {businessTeamName.length}/{maxTeamNameLength}
          </span>
        }
      />
      {false && firstRender.current && (
        <FormControl.Caption>
          {editMode ? (
            <span aria-live="polite">
              Changing the team name will break past{' '}
              <strong>
                @{businessSlug}/{businessTeamName}
              </strong>{' '}
              mentions.
            </span>
          ) : (
            <span aria-live="polite">You&apos;ll use this name to mention this team.</span>
          )}
        </FormControl.Caption>
      )}
      {hasTeamName && (
        <NameCheckValidation
          result={result}
          businessSlug={businessSlug}
          businessTeamName={businessTeamName}
          hideBlankCheck={hideBlankCheck}
        />
      )}
    </FormControl>
  )
}

BusinessTeamNameInput.displayName = 'BusinessTeamNameInput'

interface NameCheckValidationProps {
  businessTeamName: string
  businessSlug: string
  hideBlankCheck?: boolean
  result: CheckResult
}

function NameCheckValidation({businessTeamName, businessSlug, hideBlankCheck, result}: NameCheckValidationProps) {
  if (!businessTeamName) {
    return hideBlankCheck ? null : (
      <FormControl.Validation id={businessTeamNameInputDefaultMessageId} variant="error">
        New team name must not be blank
      </FormControl.Validation>
    )
  }

  switch (result.status) {
    case 'none':
      return (
        // This component is a descendant of `FormControl`
        // eslint-disable-next-line primer-react/direct-slot-children
        <FormControl.Caption
          sx={{
            height: 'var(--base-size-16)',
          }}
        >
          <span aria-live="polite">Checking availability…</span>
        </FormControl.Caption>
      )
    case 'unchanged':
      return (
        // This component is a descendant of `FormControl`
        // eslint-disable-next-line primer-react/direct-slot-children
        <FormControl.Caption>
          <span aria-live="polite">
            Changing the team name will break past{' '}
            <strong>
              @{businessSlug}/{businessTeamName}
            </strong>{' '}
            mentions
          </span>
        </FormControl.Caption>
      )
    case 'not_found':
      return (
        <FormControl.Validation id={businessTeamNameInputDefaultMessageId} variant="error">
          Not Found
        </FormControl.Validation>
      )
    case 'error':
      return result.team ? (
        <FormControl.Validation
          id={businessTeamNameInputDefaultMessageId}
          variant="error"
          sx={{
            wordBreak: 'break-word',
            display: 'flex',
            alignItems: 'center',
          }}
        >
          The team {result.error}
        </FormControl.Validation>
      ) : (
        <FormControl.Validation id={businessTeamNameInputDefaultMessageId} variant="error">
          Couldn&apos;t check availability
        </FormControl.Validation>
      )
    case 'ok':
      return (
        <FormControl.Validation id={businessTeamNameInputAvailableMessageId} variant="success">
          Team name available.
        </FormControl.Validation>
      )
    // TODO: re-enable when @mentions for Business Teams have been implemented
    // return (
    //   <FormControl.Validation id={businessTeamNameInputAvailableMessageId} variant="success">
    //     Mention this team in conversations as{' '}
    //     <strong>
    //       @{businessSlug}/{result.team}
    //     </strong>
    //   </FormControl.Validation>
    // )
  }
}
