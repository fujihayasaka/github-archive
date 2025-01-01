import {ObservableValue} from '@github-ui/observable'
import {createContext, type Dispatch, useContext, useReducer, type PropsWithChildren, useCallback} from 'react'
import {loopsAppReducer} from '../state/loops-app-reducer'
import {useDerivedObservable, useObservableValue, useObservedState} from '@github-ui/react-observable'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {PipesAction} from '../state/pipes-action'
import {defaultPipesState, type PipesState} from '../state/pipes-state'

const PipesStateContext = createContext(new ObservableValue(defaultPipesState))
const PipesDispatchContext = createContext<Dispatch<PipesAction>>(() => {})

export function PipesStateProvider({children}: PropsWithChildren) {
  const [state, _dispatch] = useReducer(loopsAppReducer, defaultPipesState)

  const stateObservable = useObservableValue(state)
  useLayoutEffect(() => {
    // eslint-disable-next-line react-hooks/react-compiler
    stateObservable.value = state
  }, [state, stateObservable])

  // This might look stupid, but putting a breakpoint in here makes
  // it a lot easier to debug where actions are getting dispatched from
  const dispatch: Dispatch<PipesAction> = useCallback(
    (action: PipesAction) => {
      _dispatch(action)
    },
    [_dispatch],
  )

  return (
    <PipesStateContext.Provider value={stateObservable}>
      <PipesDispatchContext.Provider value={dispatch}>{children}</PipesDispatchContext.Provider>
    </PipesStateContext.Provider>
  )
}

export function usePipesStateLens<T>(lens: (state: PipesState) => T): T {
  const o = useContext(PipesStateContext)
  if (!o) throw new Error('usePipesStateLens can only be used inside a PipesProvider')
  const valueObservable = useDerivedObservable(o, lens)
  return useObservedState(valueObservable)
}

export function useGetPipesState(): () => PipesState {
  const o = useContext(PipesStateContext)
  if (!o) throw new Error('useGetPipesState can only be used inside a PipesProvider')
  return useCallback(() => o.value, [o])
}

export function usePipesDispatch() {
  return useContext(PipesDispatchContext)
}
