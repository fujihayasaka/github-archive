import type {TableInstance, UseTableHooks} from 'react-table'

// eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
export function usePreventColumnAutoResize<D extends object>(hooks: UseTableHooks<D>) {
  hooks.useInstance.push(useInstance)
}

// eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
function useInstance<D extends object>(instance: TableInstance<D>) {
  // Prevent live updates from resetting column widths if the user is resizing
  Object.assign(instance, {
    autoResetResize: !instance.state.columnResizing.isResizingColumn,
  })
}
