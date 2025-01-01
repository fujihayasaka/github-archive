import {Resources} from '../../../../strings'

export class PasteValidationFailureError extends Error {
  constructor(...args: ConstructorParameters<typeof Error>) {
    super(...args)
    this.name = 'PasteValidationFailureError'
  }
}

export class DataTypeMismatchFailureError extends PasteValidationFailureError {
  constructor() {
    super(Resources.unableToPasteMismatchedDataTypes)
    this.name = 'DataTypeMismatchFailureError'
  }
}
