// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useCallback} from 'react'
import type {editor as editorTypes} from 'monaco-editor'
import type {Monaco} from '@monaco-editor/react'
import githubLightTheme from '../themes/github-light.json'
import githubDarkTheme from '../themes/github-dark.json'

export function useMonacoEditor() {
  const beforeMount = useCallback((monacoInstance: Monaco) => {
    monacoInstance.editor.defineTheme('github-light', githubLightTheme as editorTypes.IStandaloneThemeData)
    monacoInstance.editor.defineTheme('github-dark', githubDarkTheme as editorTypes.IStandaloneThemeData)
  }, [])

  return {beforeMount}
}
