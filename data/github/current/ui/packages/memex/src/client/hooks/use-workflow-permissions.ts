import {ViewerPrivileges} from '../helpers/viewer-privileges'

// eslint-disable-next-line @eslint-react/hooks-extra/no-unnecessary-use-prefix
export const useWorkflowPermissions = () => {
  const {hasWritePermissions} = ViewerPrivileges()
  return {hasWorkflowWritePermission: hasWritePermissions}
}
