// eslint-disable-next-line filenames/match-regex
import {useCallback} from 'react'
import {configureMonaco} from '../utils/monaco'
import type {editor as editorTypes} from 'monaco-editor'
import type {Monaco} from '@monaco-editor/react'
import githubLightTheme from '../themes/github-light.json'
import githubDarkTheme from '../themes/github-dark.json'

export function useMonacoEditor() {
  configureMonaco()

  const beforeMount = useCallback((monacoInstance: Monaco) => {
    monacoInstance.editor.defineTheme('github-light', githubLightTheme as editorTypes.IStandaloneThemeData)
    monacoInstance.editor.defineTheme('github-dark', githubDarkTheme as editorTypes.IStandaloneThemeData)
  }, [])

  return {beforeMount}
}
