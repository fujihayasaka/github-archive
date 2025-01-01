interface HpcTagProps {
  loading: boolean
}

export function HpcTag({loading}: HpcTagProps): JSX.Element | undefined {
  return loading ? undefined : <span data-hpc hidden />
}
