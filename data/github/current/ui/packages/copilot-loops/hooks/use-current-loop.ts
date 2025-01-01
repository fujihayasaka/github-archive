import {useLoop} from './queries/use-loop'

/**
 * A hook to get the current loop using react-query under the hood.
 * It throws an error if used outside of a context where a loop exists so Pipeline will always be present.
 */
export function useCurrentLoop() {
  const {data: loop} = useLoop()
  if (!loop) throw new Error('useCurrentLoop must be used within a context where a loop exists.')

  return loop
}
