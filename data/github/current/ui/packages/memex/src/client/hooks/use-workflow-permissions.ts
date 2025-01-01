import {ViewerPrivileges} from '../helpers/viewer-privileges'

// eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
export const useWorkflowPermissions = () => {
  const {hasWritePermissions} = ViewerPrivileges()
  return {hasWorkflowWritePermission: hasWritePermissions}
}
