import type {IssueFormRef} from '@github-ui/issue-form/Types'
import {IssueCreationKind, type IssueCreatePayload, type OnCreateProps} from '../utils/model'
import {useCallback, useEffect} from 'react'
import {useIssueCreateDataContext} from '../contexts/IssueCreateDataContext'
import type {useHandleTemplateChange} from '../use-handle-template-change'
import {issuePath} from '@github-ui/paths'

type UseOnCreateSuccessProps = {
  issueFormRef: React.RefObject<IssueFormRef>
  callback?: ({issue, createMore}: OnCreateProps) => void
  handleTemplateChange: ReturnType<typeof useHandleTemplateChange>
  navigate?: (url: string) => void
  template: IssueCreatePayload | undefined
}

export const useOnCreateSuccess = ({
  issueFormRef,
  callback,
  handleTemplateChange,
  navigate,
  template,
}: UseOnCreateSuccessProps) => {
  const {clearTitleAndBody, clearSessionData, clearSessionMetadata, clearSessionTitleAndBody, clearSessionCreateMore} =
    useIssueCreateDataContext()

  const onCreateSuccess = useCallback(
    ({issue, createMore}: OnCreateProps) => {
      callback?.({issue, createMore})
      if (createMore) {
        const effectiveTemplate = template && template.kind !== IssueCreationKind.BlankIssue ? template : undefined
        if (effectiveTemplate) {
          // For templates/forms, we retain the metadata but clear the title and body from the session storage
          clearSessionTitleAndBody()
          handleTemplateChange(template)
        } else {
          // For blank issues, we retain the metadata but clear the title and body from the components
          clearTitleAndBody()
        }
      } else {
        // Not creating more issues, so we clear all of the session data and navigating away to the new issue (if applicable)
        // clear all data from issue form elements
        issueFormRef.current?.clearSessionStorage()
        clearSessionData()
        navigate?.(
          issuePath({
            owner: issue.repository.owner.login,
            repo: issue.repository.name,
            issueNumber: issue.number,
          }),
        )
      }
    },
    [
      callback,
      issueFormRef,
      template,
      clearSessionTitleAndBody,
      handleTemplateChange,
      clearTitleAndBody,
      clearSessionData,
      navigate,
    ],
  )

  // This is to ensure that the session storage is cleared when the component unmounts (ie; when the user navigates away without canceling)
  useEffect(() => {
    return () => {
      clearSessionMetadata()
      clearSessionCreateMore()
    }
  }, [clearSessionCreateMore, clearSessionMetadata])

  return onCreateSuccess
}
