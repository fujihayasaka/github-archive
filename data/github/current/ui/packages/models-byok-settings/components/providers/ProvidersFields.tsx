import type {ValidationKind} from '../../helpers/Validation'

export type ProviderFieldProps = {
  isPending: boolean
  validation?: Record<string, ValidationKind>
}
