export function assertNever(value: never): never {
  throw new Error(`Unexpected value: ${value}`)
}

export function assertNeverWithoutThrowing(value: never): never {
  // This function is used to ensure that all possible cases are handled in a switch statement.
  // It does not throw an error, but it will cause a TypeScript error if the value is not of type 'never'.
  return value
}
