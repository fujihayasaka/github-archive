import {GearIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {memo} from 'react'

export const EditorHeaderSettings = memo(function HeaderActions({
  codeLineWrapEnabled,
  whitespaceHidden,
  problemsHidden,
  toggleCodeLineWrapEnabled,
  toggleWhitespaceHidden,
  toggleProblemsHidden,
}: {
  codeLineWrapEnabled: boolean
  whitespaceHidden: boolean
  problemsHidden: boolean
  toggleCodeLineWrapEnabled?: () => void
  toggleWhitespaceHidden?: () => void
  toggleProblemsHidden?: () => void
}) {
  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>
          <IconButton aria-label="Settings" icon={GearIcon} variant="invisible" />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay width="small">
          <ActionList>
            {(toggleCodeLineWrapEnabled || toggleWhitespaceHidden || toggleProblemsHidden) && (
              <>
                <ActionList.Divider />
                <ActionList.Group selectionVariant="multiple">
                  <ActionList.GroupHeading>Display</ActionList.GroupHeading>
                  {toggleCodeLineWrapEnabled && (
                    <ActionList.Item
                      role="menuitemcheckbox"
                      selected={codeLineWrapEnabled}
                      aria-checked={codeLineWrapEnabled}
                      onSelect={toggleCodeLineWrapEnabled}
                    >
                      Wrap lines
                    </ActionList.Item>
                  )}
                  {toggleWhitespaceHidden && (
                    <ActionList.Item
                      role="menuitemcheckbox"
                      selected={whitespaceHidden}
                      aria-checked={whitespaceHidden}
                      onSelect={toggleWhitespaceHidden}
                    >
                      Hide whitespace
                    </ActionList.Item>
                  )}
                  {toggleProblemsHidden && (
                    <ActionList.Item
                      role="menuitemcheckbox"
                      selected={problemsHidden}
                      aria-checked={problemsHidden}
                      onSelect={toggleProblemsHidden}
                    >
                      Hide problems
                    </ActionList.Item>
                  )}
                </ActionList.Group>
              </>
            )}
            {/* <ActionList.Divider />
            <ActionList.Group selectionVariant="single">
              <ActionList.GroupHeading>Show diff</ActionList.GroupHeading>
              <ShowDiffItem
                showDiff="uncommitted"
                currentShowDiff={showDiff}
                setShowDiff={setShowDiff}
                label="Uncommitted changes"
              />
              <ShowDiffItem
                showDiff="branch"
                currentShowDiff={showDiff}
                setShowDiff={setShowDiff}
                label="All changes of this branch"
              />
            </ActionList.Group> */}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
})
