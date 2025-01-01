import {assert} from './asserts'

/**
 * Function to get a random integer from a defined range.
 */
export const randomInt = (max: number, min: number = 0): number => {
  assert(!isNaN(min), '"min" param is not a number.')
  assert(!isNaN(max), '"max" param is not a number.')

  assert(isFinite(max), '"max" param is not finite.')
  assert(isFinite(min), '"min" param is not finite.')

  assert(max > min, `"max"(${max}) param should be greater than "min"(${min}).`)

  const delta = max - min
  const randomFloat = delta * Math.random()

  return Math.round(min + randomFloat)
}
