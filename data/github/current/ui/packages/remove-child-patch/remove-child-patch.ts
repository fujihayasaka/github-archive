import {isFeatureEnabled} from '@github-ui/feature-flags'

export const applyRemoveChildPatch = () => {
  if (isFeatureEnabled('remove_child_patch')) {
    if (typeof Node === 'function' && Node.prototype) {
      const originalRemoveChild = Node.prototype.removeChild
      // @ts-expect-error we always return a Node which is narrower than the function expects
      Node.prototype.removeChild = function (child) {
        try {
          return originalRemoveChild.apply(this, [child])
        } catch (e) {
          if (e instanceof Error && e.stack?.includes('react-lib')) {
            return child
          }
          throw e
        }
      }
    }
  }
}
