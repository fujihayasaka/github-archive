export function getVisibilityText(visibility: string): string {
  switch (visibility) {
    case 'org_public':
      return 'Shared'
    default:
      return 'Private'
  }
}
