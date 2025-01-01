import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useSearchParams} from '@github-ui/use-navigate'
import {GitCompareIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {memo, useCallback} from 'react'

import {useCurrentPullRequest} from '../../contexts/CurrentPullRequestProvider'
import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from '../../contexts/WorkspaceEditorUIContext'
import {setPreferredDiffStyle} from '../../utilities/preferences'
import {setQueryParam} from '../../utilities/query-params'
import type {DiffStyle, WorkspaceEditorRoutePayload} from '../../utilities/workspace-editor-types'

export const CompareDropdown = memo(function CompareDropdown() {
  const {compareRef, repo} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const dispatch = useWorkspaceEditorUIDispatch()
  const {diffStyle, showDiff} = useWorkspaceEditorUIState()
  const [, setSearchParams] = useSearchParams()

  const setDiffStyle = useCallback(
    (newDiffStyle: DiffStyle | 'hidden') => {
      if (newDiffStyle === 'hidden') {
        dispatch({type: 'SET_SHOW_DIFF', showDiff: false})
      } else {
        dispatch({type: 'SET_DIFF_STYLE', diffStyle: newDiffStyle})
        setPreferredDiffStyle(newDiffStyle)
      }
    },
    [dispatch],
  )

  const onCompareRefSelected = useCallback(
    (ref: string) => {
      dispatch({type: 'SET_SHOW_DIFF', showDiff: true})
      setQueryParam('compare_ref', ref, setSearchParams)
    },
    [dispatch, setSearchParams],
  )
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton icon={GitCompareIcon} aria-label="Compare picker" variant="invisible" />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="medium">
        <ActionList>
          <div className="px-3 py-1 d-flex flex-column">
            <span className="text-bold">Compare changes</span>
          </div>
          <ActionList.Divider />
          <ActionList.Group selectionVariant="single">
            <ActionList.GroupHeading>Compare against</ActionList.GroupHeading>
            <ActionList.Item
              selected={compareRef === pullRequest.headBranch}
              onSelect={() => onCompareRefSelected(pullRequest.headBranch)}
            >
              {`Pull request #${pullRequest.number} branch`}
              <ActionList.Description variant="block">{pullRequest.headBranch}</ActionList.Description>
            </ActionList.Item>
            <ActionList.Item
              selected={showDiff && (compareRef === repo.defaultBranch || !compareRef)}
              onSelect={() => onCompareRefSelected(repo.defaultBranch)}
            >
              Default branch
              <ActionList.Description variant="block">{repo.defaultBranch}</ActionList.Description>
            </ActionList.Item>
            {pullRequest.baseBranch !== repo.defaultBranch && (
              <ActionList.Item
                selected={showDiff && compareRef === pullRequest.baseBranch}
                onSelect={() => onCompareRefSelected(pullRequest.baseBranch)}
              >
                Pull request base branch
                <ActionList.Description variant="block">{pullRequest.baseBranch}</ActionList.Description>
              </ActionList.Item>
            )}
          </ActionList.Group>
          <ActionList.Divider />
          <ActionList.Group selectionVariant="single">
            <ActionList.GroupHeading>View</ActionList.GroupHeading>
            <ActionList.Item selected={showDiff && diffStyle === 'inline'} onSelect={() => setDiffStyle('inline')}>
              Unified
            </ActionList.Item>
            <ActionList.Item selected={showDiff && diffStyle === 'split'} onSelect={() => setDiffStyle('split')}>
              Split
            </ActionList.Item>
            <ActionList.Item selected={!showDiff} onSelect={() => setDiffStyle('hidden')}>
              Hidden
            </ActionList.Item>
          </ActionList.Group>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
})
