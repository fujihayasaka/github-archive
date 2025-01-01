import React from 'react'

// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {Button, FormControl, Spinner, Dialog} from '@primer/react'
import {ActionBar} from './ActionBar'
import {LastEditedBy, Stack} from './Ui'
import {useCopilotContentExclusionMutation} from '../hooks/use-fetchers'
import type {LastEditedPayload} from '../types'
import {RestrictionEditor} from './RestrictionEditor'
import {announce} from '@github-ui/aria-live'

const maxDocumentSize = 1000000

type Action =
  | {type: 'NEW_VALUE'; value: string}
  | {type: 'ERROR'; message: string}
  | {type: 'SUCCESS'; message: string; lastEdited?: LastEditedPayload}
  | {type: 'DISCARD'}

type State = {
  currentValue: string | null
  stableValue: string
  canDiscard: boolean
  lastEdited?: LastEditedPayload
  fieldStatus?: {status: 'error' | 'success'; message: string} | undefined
}

const reducer: React.Reducer<State, Action> = (prevState, action) => {
  switch (action.type) {
    case 'NEW_VALUE':
      if (action.value === prevState.stableValue) return prevState
      return {
        ...prevState,
        fieldStatus: undefined, // reset field status
        canDiscard: true,
        currentValue: action.value,
      }
    case 'ERROR':
      return {
        ...prevState,
        canDiscard: true,
        fieldStatus: {status: 'error', message: action.message},
      }
    case 'SUCCESS':
      return {
        ...prevState,
        stableValue: prevState.currentValue == null ? prevState.stableValue : prevState.currentValue,
        currentValue: null,
        canDiscard: false,
        lastEdited: action.lastEdited,
        fieldStatus: {status: 'success', message: action.message},
      }
    case 'DISCARD': {
      return {
        ...prevState,
        fieldStatus: undefined,
        currentValue: null,
        canDiscard: false,
      }
    }
  }
}

export function useContentExclusionMutation<Data extends {lastEdited: LastEditedPayload}>(
  endpoint: string,
  initial: {
    value: string
    lastEdited?: LastEditedPayload
  },
) {
  const {addToast} = useToastContext()

  const [save, loading] = useCopilotContentExclusionMutation<{paths: string}, Data>(endpoint, 'PUT')

  const [state, dispatch] = React.useReducer<typeof reducer>(reducer, {
    stableValue: initial.value,
    currentValue: null,
    lastEdited: initial.lastEdited,
    canDiscard: false,
  })

  const currentValue = React.useRef<string>(state.stableValue)
  currentValue.current = state.currentValue != null ? state.currentValue : state.stableValue

  const onChange = React.useCallback((value: string) => void dispatch({type: 'NEW_VALUE', value}), [dispatch])
  const onDiscard = React.useCallback(() => void dispatch({type: 'DISCARD'}), [dispatch])
  const onSave = React.useCallback(() => {
    save({
      payload: {paths: currentValue.current},
      onError(e) {
        let message = 'Something went wrong. Please try again later.'
        if (e && typeof e === 'object' && 'message' in e) message = String(e.message)
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          message: 'Excluded paths not updated, check the errors and try again.',
          role: 'alert',
          type: 'error',
        })
        dispatch({type: 'ERROR', message})
        announce(message, {assertive: true})
      },
      onComplete(data, status) {
        let message = 'Excluded paths updated.'
        if (data && typeof data === 'object' && 'message' in data) message = String(data.message)

        if (status === 200 && data) {
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            message: 'Excluded paths updated.',
            role: 'status',
            type: 'success',
          })
        }

        dispatch({type: 'SUCCESS', message, lastEdited: data?.lastEdited})
        announce(message, {assertive: true})
      },
    })
  }, [save, dispatch, addToast])

  return {
    value: currentValue.current,
    lastEdited: state.lastEdited,
    fieldStatus: state.fieldStatus,
    canDiscard: state.canDiscard,
    stableValue: state.stableValue,
    loading,
    onDiscard,
    onChange,
    onSave,
  }
}

export function ContentExclusionPaths(props: {
  endpoint: string
  initialValue: string
  initialLastEdited?: LastEditedPayload
  label: string
  placeholder: string
  contentExclusionSaveSpeedbumpFlag: boolean
}) {
  const {endpoint, initialLastEdited, initialValue, label, placeholder, contentExclusionSaveSpeedbumpFlag} = props
  const [saveDialogOpen, setSaveDialogOpen] = React.useState(false)
  const saveRef = React.useRef<HTMLButtonElement>(null)

  const {value, stableValue, lastEdited, fieldStatus, loading, canDiscard, onDiscard, onChange, onSave} =
    useContentExclusionMutation(endpoint, {
      value: initialValue,
      lastEdited: initialLastEdited,
    })

  const openSaveDialog = React.useCallback(() => {
    if (contentExclusionSaveSpeedbumpFlag && !!stableValue.length && !value.length) {
      setSaveDialogOpen(true)
    } else {
      onSave()
    }
  }, [stableValue, value, onSave, contentExclusionSaveSpeedbumpFlag])
  const dialogSave = React.useCallback(() => {
    onSave()
    setSaveDialogOpen(false)
  }, [onSave])
  const dismissSaveDialog = React.useCallback(() => {
    onDiscard()
    setSaveDialogOpen(false)
  }, [onDiscard])

  const editorId = React.useId()
  const editorLabeledById = React.useId()

  return (
    <Stack space="spacious">
      <FormControl id={editorId}>
        <FormControl.Label id={editorLabeledById}>{label}</FormControl.Label>
        {loading ? (
          <FormControl.Caption sx={{display: 'flex'}}>
            <Spinner size="small" />
            &nbsp;Checking syntax
          </FormControl.Caption>
        ) : fieldStatus ? (
          <FormControl.Validation variant={fieldStatus.status} sx={{paddingBottom: '2px'}}>
            {fieldStatus.message}
          </FormControl.Validation>
        ) : (value?.length || 0) > maxDocumentSize ? (
          <FormControl.Validation variant="error" sx={{paddingBottom: '2px'}}>
            You have {value.length} characters, but the maximum is {maxDocumentSize}
          </FormControl.Validation>
        ) : (
          <FormControl.Caption>
            Use separate lines to choose which folders and files will be excluded by GitHub Copilot
          </FormControl.Caption>
        )}
        <RestrictionEditor
          fieldStatus={fieldStatus?.status}
          labelId={editorLabeledById}
          onChange={onChange}
          placeholder={placeholder}
          value={value}
        />
      </FormControl>

      <ActionBar>
        {lastEdited && (
          <ActionBar.Details>
            <LastEditedBy {...lastEdited} />
          </ActionBar.Details>
        )}
        <Button disabled={!canDiscard} variant="default" onClick={onDiscard}>
          Discard changes
        </Button>
        <Button variant="primary" onClick={openSaveDialog} ref={saveRef}>
          Save changes
        </Button>
      </ActionBar>
      {contentExclusionSaveSpeedbumpFlag && saveDialogOpen && (
        <Dialog
          data-testid="content-exclusion-save-dialog"
          aria-labelledby="content-exclusion-save-dialog-title"
          title="Delete excluded paths"
          returnFocusRef={saveRef}
          onClose={dismissSaveDialog}
          footerButtons={[
            {buttonType: 'default', content: 'Cancel', onClick: dismissSaveDialog},
            {
              buttonType: 'primary',
              content: 'Confirm',
              autoFocus: true,
              onClick: dialogSave,
            },
          ]}
        >
          You are about to delete all excluded paths. Are you sure you want to proceed?
        </Dialog>
      )}
    </Stack>
  )
}
