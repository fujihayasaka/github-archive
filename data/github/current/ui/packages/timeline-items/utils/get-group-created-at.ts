type RollupGroup = {createdAt?: string}

export function getGroupCreatedAt(createdAt: string | undefined, rollupGroup: RollupGroup[]) {
  if (rollupGroup.length === 0) {
    return createdAt
  }
  let latest = undefined

  if (createdAt) {
    latest = new Date(createdAt).valueOf()
  }

  for (const event of rollupGroup) {
    if (event.createdAt) {
      const current = new Date(event.createdAt).valueOf()
      if (!latest || current > latest) {
        latest = current
      }
    }
  }

  return latest
}
