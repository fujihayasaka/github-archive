import {isFeatureEnabled} from '@github-ui/feature-flags'

export const applyInsertBeforePatch = () => {
  if (isFeatureEnabled('insert_before_patch')) {
    if (typeof Node === 'function' && Node.prototype) {
      const originalInsertBefore = Node.prototype.insertBefore
      Node.prototype.insertBefore = function <T extends Node>(node: T, child: Node | null): T {
        try {
          // @ts-expect-error some subtyping constraints
          return originalInsertBefore.apply(this, [node, child])
        } catch (e) {
          if (e instanceof Error && (e.stack?.includes('react-lib') || e.stack?.includes('react-dom'))) {
            return node
          }
          throw e
        }
      }
    }
  }
}
