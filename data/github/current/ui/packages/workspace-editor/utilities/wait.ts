/**
 * Wait on `delay` milliseconds asynronously before proceeding.
 */
export const wait = (delay: number) => {
  return new Promise(resolve => {
    setTimeout(resolve, delay)
  })
}
