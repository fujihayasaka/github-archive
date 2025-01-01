import {useQuery} from '@github-ui/react-query'
import {loadWASM, OnigScanner, OnigString} from 'vscode-oniguruma'
import onigWasmPath from 'vscode-oniguruma/release/onig.wasm'
import type {IOnigLib} from 'vscode-textmate'

// CSP is behind `copilot_workbench_monaco_wasm` ff
const fetchWasm = async () => {
  try {
    const response = await fetch(onigWasmPath)
    if (!response.ok) {
      throw new Error(`Failed to fetch WASM: ${response.status} ${response.statusText}`)
    }

    const bytes = await response.arrayBuffer()
    await loadWASM(bytes)
    const vscodeOnigurumaLib = {
      createOnigScanner(patterns: string[]) {
        return new OnigScanner(patterns)
      },
      createOnigString(s: string) {
        return new OnigString(s)
      },
    } as IOnigLib
    return vscodeOnigurumaLib
  } catch (error) {
    // If the WASM file does not load, it might be because:
    // 1. the feature flag is off to enable CSP (copilot_workbench_monaco_wasm), or
    // 2. the browser does not support WASM
    // eslint-disable-next-line no-console
    console.error('WASM loading failed:', error)
    throw error
  }
}

export const useOnigurumaWasm = () =>
  useQuery({
    queryKey: ['onigurumaWasmModule'],
    queryFn: fetchWasm,
    staleTime: Infinity,
    retry: false,
  })
