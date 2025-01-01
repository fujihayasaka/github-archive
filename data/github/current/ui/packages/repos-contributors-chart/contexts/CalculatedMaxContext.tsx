import type React from 'react'
import {createContext, useCallback, useContext, useEffect, useMemo, useRef, useState} from 'react'

export type CalculatedMaxContextValues = {
  max: number
  addValue(value: number): void
  reset(): void
}

export const CalculatedMaxContext = createContext<CalculatedMaxContextValues>({} as CalculatedMaxContextValues)

export function CalculatedMaxProvider({children}: React.PropsWithChildren) {
  const [max, setMax] = useState<number>(0)
  const [values, setValues] = useState<number[]>([])
  const debounceHandler = useRef<NodeJS.Timeout | undefined>(undefined)

  const reset = useCallback(() => {
    setValues([])
  }, [setValues])

  const addValue = useCallback(
    (value: number) => {
      setValues(currentValues => [...currentValues, value])
    },
    [setValues],
  )

  const calculateMax = useCallback(
    (_values: number[]) => {
      const absoluteMax = Math.max(0, ..._values)
      const paddedMax = Math.ceil(absoluteMax + absoluteMax / 10)
      setMax(paddedMax)
    },
    [setMax],
  )

  useEffect(() => {
    if (values.length === 0) {
      return
    }
    debounceHandler.current = setTimeout(() => {
      calculateMax(values)
    }, 200)

    return () => clearTimeout(debounceHandler.current)
  }, [values, calculateMax])

  const calculatedMaxValue = useMemo(
    () => ({
      max,
      addValue,
      reset,
    }),
    [max, addValue, reset],
  )

  return <CalculatedMaxContext.Provider value={calculatedMaxValue}>{children}</CalculatedMaxContext.Provider>
}

export function useCalculatedMax() {
  return useContext(CalculatedMaxContext)
}
