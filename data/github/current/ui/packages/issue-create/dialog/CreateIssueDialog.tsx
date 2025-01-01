import {Portal} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useCallback, type RefObject, useMemo} from 'react'
import {useIssueCreateConfigContext} from '../contexts/IssueCreateConfigContext'
import type {OnCreateProps} from '../utils/model'
import {CreateIssueDialogHeader} from './CreateIssueDialogHeader'
import {DisplayMode} from '../utils/display-mode'
import {CreateIssueFooter} from '../CreateIssueFooter'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {CreateIssueDialog$key} from './__generated__/CreateIssueDialog.graphql'
import {CreateIssue, type CreateIssueProps} from '../CreateIssue'
import {useSafeClose} from '../hooks/use-safe-close'
import {useIssueCreateDataContext} from '../contexts/IssueCreateDataContext'

type CreateIssueDialogProps = Omit<CreateIssueProps, 'currentRepository' | 'onSafeClose'> & {
  currentRepository: CreateIssueDialog$key | undefined | null
  returnFocusRef?: RefObject<HTMLElement>
}

export const CreateIssueDialog = ({
  onCreateSuccess,
  onCancel,
  navigate,
  currentRepository,
  isNavigatingToNew,
  returnFocusRef,
  ...props
}: CreateIssueDialogProps): JSX.Element => {
  const {optionConfig, initialDefaultDisplayMode, setDisplayMode, displayMode, setCreateMore} =
    useIssueCreateConfigContext()
  const {usedStorageKeyPrefix} = useIssueCreateDataContext()
  const data = useFragment(
    graphql`
      fragment CreateIssueDialog on Repository
      @argumentDefinitions(includeTemplates: {type: "Boolean", defaultValue: false}) {
        ...CreateIssue @arguments(includeTemplates: $includeTemplates)
      }
    `,
    currentRepository,
  )

  const onCancelInternal = useCallback(() => {
    setCreateMore(false)
    setDisplayMode(initialDefaultDisplayMode)

    onCancel()
  }, [initialDefaultDisplayMode, onCancel, setCreateMore, setDisplayMode])

  const {onSafeClose} = useSafeClose({
    storageKeyPrefix: usedStorageKeyPrefix,
    issueFormRef: props.issueFormRef,
    onCancel: onCancelInternal,
  })

  const resetDisplayModeOnCreateSuccess = useCallback(
    ({issue, createMore}: OnCreateProps) => {
      onCreateSuccess({issue, createMore})
      if (!createMore) {
        setDisplayMode(initialDefaultDisplayMode)
      }
    },
    [initialDefaultDisplayMode, onCreateSuccess, setDisplayMode],
  )

  const issueDialogProps = {...props, onCancel: onSafeClose}

  const showCreateDialog = useMemo(() => {
    return !isNavigatingToNew || !optionConfig.canBypassTemplateSelection
  }, [isNavigatingToNew, optionConfig.canBypassTemplateSelection])

  return (
    <Portal>
      <Dialog
        returnFocusRef={returnFocusRef}
        renderHeader={headerProps => <CreateIssueDialogHeader navigate={navigate} {...headerProps} />}
        renderFooter={() => {
          if (displayMode === DisplayMode.IssueCreation || displayMode === DisplayMode.IssueDuplication) {
            return (
              <Dialog.Footer>
                <CreateIssueFooter onClose={() => onSafeClose()} {...props} />
              </Dialog.Footer>
            )
          }
          return null
        }}
        renderBody={() => (
          <div
            className={`${
              displayMode === DisplayMode.IssueCreation || displayMode === DisplayMode.IssueDuplication ? 'p-3' : 'p-0'
            }`}
          >
            <CreateIssue
              onCreateSuccess={resetDisplayModeOnCreateSuccess}
              navigate={navigate}
              currentRepository={data}
              {...issueDialogProps}
            />
          </div>
        )}
        onClose={onSafeClose}
        width="xlarge"
        height="auto"
        sx={{
          width: '100%',
          margin: 4,
          maxWidth: '800px',
          maxHeight: 'clamp(300px, 80vh, 800px)',
          visibility: showCreateDialog ? 'visible' : 'hidden',
        }}
      />
    </Portal>
  )
}
