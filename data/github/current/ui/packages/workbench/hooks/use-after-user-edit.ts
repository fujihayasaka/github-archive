import {useDebounce} from '@github-ui/use-debounce'

import {useStableCallback} from './use-stable-callback'
import {useWorkbench} from './use-workbench'

export const useSaveUserEdit = () => {
  const {persistUserEdit} = useWorkbench()
  const save = useStableCallback(async (message: string, path: string) => {
    await persistUserEdit(message, path)
  })
  const debouncedSave = useDebounce(save, 750)

  return debouncedSave
}
