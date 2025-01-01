// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useCallback} from 'react'
import type {editor as editorTypes} from 'monaco-editor'
import type {Monaco} from '@monaco-editor/react'
import githubLightTheme from '../themes/github-light.json'
import githubDarkTheme from '../themes/github-dark.json'

export function useMonacoEditor(disableDefaultJsTsLspFeatures?: boolean) {
  const beforeMount = useCallback(
    (monacoInstance: Monaco) => {
      // Based on the GitHub VS Code theme (https://github.com/primer/github-vscode-theme?tab=readme-ov-file),
      // extracted `colors` from the generated `dark-default.json` and `light-default.json` files,
      // then converted the files to Monaco theme format, and utilized the `rules` property.
      // Added manual overrides at the end to `rules` to match GitHub theme.
      monacoInstance.editor.defineTheme('github-light', githubLightTheme as editorTypes.IStandaloneThemeData)
      monacoInstance.editor.defineTheme('github-dark', githubDarkTheme as editorTypes.IStandaloneThemeData)
      if (disableDefaultJsTsLspFeatures) {
        disableLanguageFeaturesFromJsTsWorker(monacoInstance)
      }
    },
    [disableDefaultJsTsLspFeatures],
  )

  return {beforeMount}
}
/**
 * Disable language features from the JS/TS worker
 * This is needed to avoid conflicts with the LSP server provided by the codespace
 * @param monacoInstance - Monaco instance
 */
function disableLanguageFeaturesFromJsTsWorker(monacoInstance: Monaco) {
  monacoInstance.languages.typescript.javascriptDefaults.setCompilerOptions({
    ...monacoInstance.languages.typescript.javascriptDefaults.getCompilerOptions(),
    allowNonTsExtensions: true,
    noLib: true,
  })
  monacoInstance.languages.typescript.typescriptDefaults.setCompilerOptions({
    ...monacoInstance.languages.typescript.typescriptDefaults.getCompilerOptions(),
    noLib: true,
  })
  monacoInstance.languages.typescript.javascriptDefaults.setDiagnosticsOptions({
    noSemanticValidation: true,
    noSyntaxValidation: true,
  })
  monacoInstance.languages.typescript.typescriptDefaults.setDiagnosticsOptions({
    noSemanticValidation: true,
    noSyntaxValidation: true,
  })
  monacoInstance.languages.typescript.javascriptDefaults.setModeConfiguration({
    hovers: false,
    completionItems: false,
    diagnostics: false,
    definitions: false,
  })
  monacoInstance.languages.typescript.typescriptDefaults.setModeConfiguration({
    hovers: false,
    completionItems: false,
    diagnostics: false,
    definitions: false,
  })
}
