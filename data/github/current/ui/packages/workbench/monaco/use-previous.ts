/* https://github.com/suren-atoyan/monaco-react/blob/master/src/hooks/usePrevious/index.ts
 * Split from package to apply edits instead of setting value
 *
 * @monaco-editor/react
 * Copyright (c) 2018 Suren Atoyan
 * MIT License: https://github.com/suren-atoyan/monaco-react?tab=MIT-1-ov-file
 */
import {useEffect, useRef} from 'react'

function usePrevious<T>(value: T) {
  const ref = useRef<T | null>(null)

  useEffect(() => {
    ref.current = value
  }, [value])

  return ref.current
}

export default usePrevious
