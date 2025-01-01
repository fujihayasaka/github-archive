import type {Pipeline} from '../types/app'
import {useLoop} from './queries/use-loop'

/**
 * Loads the current loop using react-query, runs a selector function on it, and returns the result.
 */
export function useLoopLens<T>(selector: (pipeline: Pipeline | undefined | null) => T): T {
  const {data: loop} = useLoop()
  return selector(loop)
}
