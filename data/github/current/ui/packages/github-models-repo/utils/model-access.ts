const allRestrictedModelNames = ['o1', 'o1-mini', 'o1-preview', 'o3-mini']

export const userHasAccessToModel = (name: string, restrictedModels: string[]) => {
  if (allRestrictedModelNames.includes(name)) {
    return restrictedModels.includes(name)
  }
  return true
}
