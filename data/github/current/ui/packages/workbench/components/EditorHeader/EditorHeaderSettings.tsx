import {CheckIcon, CopyIcon, GearIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {memo, useCallback, useState} from 'react'

export const EditorHeaderSettings = memo(function HeaderActions({
  onCopyFileContents,
  codeLineWrapEnabled,
  whitespaceHidden,
  problemsHidden,
  setCodeLineWrapEnabled,
  setWhitespaceHidden,
  setProblemsHidden,
}: {
  onCopyFileContents?: () => void
  codeLineWrapEnabled: boolean
  whitespaceHidden: boolean
  problemsHidden: boolean
  setCodeLineWrapEnabled: (state: boolean) => void
  setWhitespaceHidden: (state: boolean) => void
  setProblemsHidden: (state: boolean) => void
}) {
  const [successfulCopy, setSuccessfulCopy] = useState(false)

  const toggleCodeLineWrapEnabled = useCallback(() => {
    setCodeLineWrapEnabled(!codeLineWrapEnabled)
  }, [codeLineWrapEnabled, setCodeLineWrapEnabled])

  const toggleWhitespaceHidden = useCallback(() => {
    setWhitespaceHidden(!whitespaceHidden)
  }, [setWhitespaceHidden, whitespaceHidden])

  const toggleProblemsHidden = useCallback(() => {
    setProblemsHidden(!problemsHidden)
  }, [problemsHidden, setProblemsHidden])

  const handleFileCopy = useCallback(() => {
    onCopyFileContents?.()
    setSuccessfulCopy(true)
    setTimeout(() => {
      setSuccessfulCopy(false)
    }, 1000)
  }, [onCopyFileContents])

  return (
    <>
      <IconButton
        icon={successfulCopy ? CheckIcon : CopyIcon}
        onClick={handleFileCopy}
        aria-label="Copy file contents"
        variant="invisible"
        className={successfulCopy ? 'fgColor-success' : 'fgColor-muted'}
      />
      <ActionMenu>
        <ActionMenu.Anchor>
          <IconButton aria-label="File options" icon={GearIcon} variant="invisible" />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay width="small">
          <ActionList>
            <ActionList.Group selectionVariant="multiple">
              <ActionList.GroupHeading>Code display</ActionList.GroupHeading>
              <ActionList.Item
                role="menuitemcheckbox"
                selected={codeLineWrapEnabled}
                aria-checked={codeLineWrapEnabled}
                onSelect={toggleCodeLineWrapEnabled}
              >
                Wrap lines
              </ActionList.Item>

              <ActionList.Item
                role="menuitemcheckbox"
                selected={whitespaceHidden}
                aria-checked={whitespaceHidden}
                onSelect={toggleWhitespaceHidden}
              >
                Hide whitespace
              </ActionList.Item>

              <ActionList.Item
                role="menuitemcheckbox"
                selected={problemsHidden}
                aria-checked={problemsHidden}
                onSelect={toggleProblemsHidden}
              >
                Hide problems
              </ActionList.Item>
            </ActionList.Group>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
})
