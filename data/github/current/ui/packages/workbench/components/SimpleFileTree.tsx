import {useNavigate} from '@github-ui/use-navigate'
import {FileIcon} from '@primer/octicons-react'
import {TreeView} from '@primer/react'
//@ts-expect-error shares types with Object.groupBy
import groupBy from 'object.groupby'
import {useMemo} from 'react'
import {useLocation} from 'react-router-dom'

import {useEditorContext} from '../contexts/EditorContext'
import {useFilesContext} from '../contexts/FilesContext'
import {useWorkbenchContext} from '../contexts/WorkbenchContext'
import {buildFileTree} from '../utilities/files'

function SubTree(props: {base: string; items: Record<string, unknown>; workbenchId: string; isFetching: boolean}) {
  const {base, items, workbenchId, isFetching} = props

  // Group directories before files
  const grouped = (groupBy as typeof Object.groupBy)(Object.entries(items), ([_, kids]) => {
    return kids !== null ? 'dirs' : 'files'
  })

  const directories = (grouped.dirs || [])
    .sort(([lpath, _l], [rpath, _r]) => lpath.localeCompare(rpath))
    .map(([path, kids]) => {
      return (
        <DirectoryTreeViewItem
          key={base + path}
          base={base}
          path={path}
          items={kids as Record<string, unknown>}
          workbenchId={workbenchId}
          isFetching={isFetching}
        />
      )
    })

  const files = (grouped.files || [])
    .sort(([lpath, _l], [rpath, _r]) => lpath.localeCompare(rpath))
    .map(([path, _]) => {
      return (
        <FileTreeViewItem key={base + path} base={base} path={path} workbenchId={workbenchId} isFetching={isFetching} />
      )
    })

  return (
    <>
      {directories}
      {files}
    </>
  )
}

function FileTreeViewItem(props: {base: string; path: string; workbenchId: string; isFetching: boolean}) {
  const {base, path, workbenchId} = props

  const location = useLocation()
  const navigate = useNavigate()
  const {forceEditorRefresh} = useEditorContext()
  const {sparkFileUrl} = useWorkbenchContext()

  const id = `${base}/${path}`

  const url = sparkFileUrl({sparkId: workbenchId, path: id.replace(/^\//, '')})

  const isSelected = location.pathname === url

  return (
    <TreeView.Item
      id={id}
      key={id}
      current={isSelected}
      onSelect={() => {
        if (location.pathname !== url) forceEditorRefresh()
        navigate(url)
      }}
    >
      <TreeView.LeadingVisual>
        <FileIcon />
      </TreeView.LeadingVisual>
      {path}
    </TreeView.Item>
  )
}

function DirectoryTreeViewItem(props: {
  base: string
  path: string
  items: Record<string, unknown>
  workbenchId: string
  isFetching: boolean
}) {
  const {base, path, items, workbenchId, isFetching} = props
  const id = `${base}/${path}`
  return (
    <TreeView.Item id={id} key={id} defaultExpanded>
      <TreeView.LeadingVisual>
        <TreeView.DirectoryIcon />
      </TreeView.LeadingVisual>
      {path}
      <TreeView.SubTree>
        <SubTree base={id} items={items} workbenchId={workbenchId} isFetching={isFetching} />
      </TreeView.SubTree>
    </TreeView.Item>
  )
}

interface FileTreeProps {
  workbenchId: string
  isFetching: boolean
}

export function SimpleFileTree({workbenchId, isFetching}: FileTreeProps) {
  // V2 stuff
  const {getFileList} = useFilesContext()
  const fileList = getFileList()

  const fileTree = useMemo(() => {
    const files = fileList.map(file => file.path)
    return buildFileTree(files)
  }, [fileList])

  return (
    <TreeView aria-label="Files changed">
      <SubTree base="" items={fileTree} workbenchId={workbenchId} isFetching={isFetching} />
    </TreeView>
  )
}
