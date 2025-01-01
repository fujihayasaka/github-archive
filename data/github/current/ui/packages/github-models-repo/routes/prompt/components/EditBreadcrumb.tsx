import {repoModelsPath, type Repository} from '@github-ui/paths'
import {Breadcrumbs, TextInput} from '@primer/react'
import {useCallback, useState} from 'react'
import {usePromptCompareManager} from '../prompt-compare-manager'

// EditBreadCrumb is initial forked from:
// app/assets/modules/react-code-view/components/blob-edit/BlobEditor.tsx
// since the original component is not in a shared package, nor is the component exported, we need to copy it here
// Furthermore, it uses the deprecated primer-react Breadcrumbs component, and we use the new one
export function EditBreadcrumb({
  folderPath: initialFolderPath,
  fileName: initialFileName,
  nameInputRef,
  repository,
}: {
  folderPath: string
  fileName: string
  nameInputRef: React.RefObject<HTMLInputElement>
  repository: Repository
}) {
  const [fileName, setFileName] = useState(initialFileName)
  const [folderPath, setFolderPath] = useState(initialFolderPath)
  const manager = usePromptCompareManager()

  const onFileNameInputKeyPress = useCallback(
    (event: React.KeyboardEvent<HTMLInputElement>) => {
      if (
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        event.key === 'Backspace' &&
        folderPath.length > 0 &&
        nameInputRef.current?.selectionStart === 0 &&
        nameInputRef.current?.selectionEnd === 0
      ) {
        const pathParts = folderPath.split('/')
        const unchangedPathParts = pathParts.slice(0, -2)

        const newFolderPath = unchangedPathParts.length ? `${unchangedPathParts.join('/')}/` : ''
        const newFileName = pathParts[pathParts.length - 2] + fileName

        const partLength = pathParts[pathParts.length - 2]!.length
        event.preventDefault()
        window.requestAnimationFrame(() => {
          nameInputRef.current?.setSelectionRange(partLength, partLength)
        })

        setFileName(newFileName)
        setFolderPath(newFolderPath)
      }
    },
    [fileName, folderPath, nameInputRef],
  )

  const onFileNameChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const value = event.target.value
      let newFileName = fileName
      let newFolderPath = folderPath

      if (value.includes('/')) {
        const pathParts = value.split('/')

        if (value.endsWith('/')) {
          newFileName = ''
          newFolderPath = `${folderPath}${value}`
        } else {
          newFileName = pathParts[pathParts.length - 1] ?? ''
          newFolderPath = `${folderPath}${pathParts.slice(0, -1).join('/')}/`

          if (pathParts.length > 1) {
            window.requestAnimationFrame(() => {
              nameInputRef.current?.setSelectionRange(0, 0)
            })
          }
        }
      } else {
        newFileName = value
      }

      newFolderPath = normalizeRelativePathChange(newFolderPath)

      setFolderPath(newFolderPath)
      setFileName(newFileName)

      let path
      if (newFileName) {
        path = `${newFolderPath}${newFileName}`
        path = path.endsWith('.prompt.yml') || path.endsWith('.prompt.yaml') ? path : `${path}.prompt.yml`
      } else {
        path = ''
      }
      manager.updatePromptPath(path)
    },
    [fileName, folderPath, manager, nameInputRef],
  )

  return (
    <Breadcrumbs>
      <Breadcrumbs.Item
        className="text-bold"
        href={repoModelsPath({
          repo: repository,
          action: 'prompts',
        })}
      >
        Prompts
      </Breadcrumbs.Item>
      {folderPath
        .split('/')
        .filter(segment => segment !== '')
        .map((folder, index) => (
          <Breadcrumbs.Item
            // using index in addition to segment to ensure unique keys
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={`${folder}-${index}`}
          >
            {folder}
          </Breadcrumbs.Item>
        ))}

      <Breadcrumbs.Item>
        <TextInput
          aria-label="File name"
          onChange={onFileNameChange}
          onKeyDown={onFileNameInputKeyPress}
          value={fileName}
          ref={nameInputRef}
          placeholder="Name your file..."
        />
      </Breadcrumbs.Item>
    </Breadcrumbs>
  )
}

/**
 * Normalize relative changes (../) in the folder path
 * @param folderPath the folder path to normalize
 * @returns {string} the normalized folder path with relative changes applied
 */
export function normalizeRelativePathChange(folderPath: string) {
  let newFolderPath = folderPath

  // dont try to relative path out of the repo
  if (newFolderPath === '../') {
    newFolderPath = ''
  }

  const parts = newFolderPath.split('/')

  // if the second to last part is '..', remove the last two parts to go up a folder
  // last part is the / at the end of the folder path
  if (parts.length > 2 && parts[parts.length - 2] === '..') {
    parts.pop() // remove the trailing /
    parts.pop() // remove the ..
    parts.pop() // remove the preceding folder

    if (parts.length === 0) {
      newFolderPath = ''
    } else {
      newFolderPath = `${parts.join('/')}/`
    }
  }

  return newFolderPath
}
