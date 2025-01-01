/*
 * File based from https://github.com/zikaari/monaco-editor-textmate/blob/master/src/tm-to-monaco-token.ts
 * Split from package to use vscode-textmate
 *
 * monaco-editor-textmate
 * Copyright (c) 2018 Neek Sandhu
 * MIT license: https://github.com/zikaari/monaco-editor-textmate?tab=MIT-1-ov-file#readme
 */
import type {editor as MonacoEditor} from 'monaco-editor'

export const TMToMonacoToken = (editor: MonacoEditor.ICodeEditor, scopes: string[]) => {
  let scopeName = ''
  // get the scope name. Example: cpp , java, haskell
  if (scopes[0]) {
    for (let i = scopes[0].length - 1; i >= 0; i -= 1) {
      const char = scopes[0][i]
      if (char === '.') {
        break
      }
      scopeName = char + scopeName
    }
  }

  // iterate through all scopes from last to first
  for (let i = scopes.length - 1; i >= 0; i -= 1) {
    const scope = scopes[i]

    /**
     * Try all possible tokens from high specific token to low specific token
     *
     * Example:
     * 0 meta.function.definition.parameters.cpp
     * 1 meta.function.definition.parameters
     *
     * 2 meta.function.definition.cpp
     * 3 meta.function.definition
     *
     * 4 meta.function.cpp
     * 5 meta.function
     *
     * 6 meta.cpp
     * 7 meta
     */
    if (scope) {
      for (let j = scope.length - 1; j >= 0; j -= 1) {
        const char = scope[j]
        if (char === '.') {
          const token = scope.slice(0, j)
          const themeService = (
            editor as unknown as {
              _themeService: {_theme: {_tokenTheme: {_match: (token: string) => {_foreground: number}}}}
            }
          )['_themeService']
          if (themeService && themeService._theme._tokenTheme._match(`${token}.${scopeName}`)._foreground > 1) {
            return `${token}.${scopeName}`
          }
          if (themeService._theme._tokenTheme._match(token)._foreground > 1) {
            return token
          }
        }
      }
    }
  }

  return ''
}
