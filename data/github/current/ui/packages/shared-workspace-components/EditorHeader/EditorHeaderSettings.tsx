import {GearIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {memo, useCallback} from 'react'

type LayoutOptions = 'inline' | 'split' | 'hidden'
type ShowDiffOptions = 'latest' | 'uncommitted' | 'branch'

type LayoutItemProps = {
  layout: LayoutOptions
  currentLayout: LayoutOptions
  setLayout: (layout: LayoutOptions) => void
  label: string
}

type ShowDiffItemProps = {
  showDiff: ShowDiffOptions
  currentShowDiff: ShowDiffOptions
  setShowDiff: (showDiff: ShowDiffOptions) => void
  label: string
}

const LayoutItem = ({layout, currentLayout, setLayout, label}: LayoutItemProps) => (
  <ActionList.Item
    role="menuitemcheckbox"
    selected={layout === currentLayout}
    aria-checked={layout === currentLayout}
    onSelect={useCallback(() => setLayout(layout), [setLayout, layout])}
  >
    {label}
  </ActionList.Item>
)

const ShowDiffItem = ({showDiff, currentShowDiff, setShowDiff, label}: ShowDiffItemProps) => (
  <ActionList.Item
    role="menuitemcheckbox"
    selected={showDiff === currentShowDiff}
    aria-checked={showDiff === currentShowDiff}
    onSelect={useCallback(() => setShowDiff(showDiff), [setShowDiff, showDiff])}
  >
    {label}
  </ActionList.Item>
)

export const EditorHeaderSettings = memo(function HeaderActions({
  layout,
  showDiff,
  setLayout,
  setShowDiff,
  codeLineWrapEnabled,
  whitespaceHidden,
  problemsHidden,
  toggleCodeLineWrapEnabled,
  toggleWhitespaceHidden,
  toggleProblemsHidden,
}: {
  layout: LayoutOptions
  showDiff: ShowDiffOptions
  setLayout: (layout: LayoutOptions) => void
  setShowDiff: (showDiff: ShowDiffOptions) => void
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
            <ActionList.Group selectionVariant="single">
              <ActionList.GroupHeading>Layout</ActionList.GroupHeading>
              <LayoutItem layout="inline" currentLayout={layout} setLayout={setLayout} label="Unified" />
              <LayoutItem layout="split" currentLayout={layout} setLayout={setLayout} label="Split" />
              <LayoutItem layout="hidden" currentLayout={layout} setLayout={setLayout} label="Hide diff" />
            </ActionList.Group>
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
            <ActionList.Divider />
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
            </ActionList.Group>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
})
