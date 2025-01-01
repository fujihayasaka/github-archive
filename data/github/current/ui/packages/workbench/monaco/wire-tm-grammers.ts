/*
 * File based from https://github.com/zikaari/monaco-editor-textmate/blob/master/src/index.ts
 * Split from package to use vscode-textmate
 *
 * monaco-editor-textmate
 * Copyright (c) 2018 Neek Sandhu
 * MIT license: https://github.com/zikaari/monaco-editor-textmate?tab=MIT-1-ov-file#readme
 */
import type {Monaco} from '@monaco-editor/react'
import type {editor as MonacoEditor, languages} from 'monaco-editor'
import type {Registry, StateStack} from 'vscode-textmate'
import {INITIAL} from 'vscode-textmate'

import {TMToMonacoToken} from './tm-to-monaco-token'

class TokenizerState implements languages.IState {
  private _ruleStack: StateStack

  constructor(ruleStack: StateStack) {
    this._ruleStack = ruleStack
  }

  public get ruleStack(): StateStack {
    return this._ruleStack
  }

  public clone(): TokenizerState {
    return new TokenizerState(this._ruleStack)
  }

  public equals(other: languages.IState): boolean {
    if (!other || !(other instanceof TokenizerState) || other !== this || other._ruleStack !== this._ruleStack) {
      return false
    }
    return true
  }
}

/**
 * Wires up monaco-editor with vscode-textmate
 *
 * @param monaco monaco namespace this operation should apply to (usually the `monaco` global unless you have some other setup)
 * @param registry TmGrammar `Registry` this wiring should rely on to provide the grammars
 * @param languages `Map` of language ids (string) to TM names (string)
 */
export function wireTmGrammars(
  monaco: Monaco,
  registry: Registry,
  languages: Map<string, string>,
  editor?: MonacoEditor.ICodeEditor,
) {
  return Promise.all(
    Array.from(languages.keys()).map(async languageId => {
      const tmName = languages.get(languageId)
      const grammar = tmName && (await registry.loadGrammar(tmName))
      if (grammar) {
        monaco.languages.setTokensProvider(languageId, {
          getInitialState: () => new TokenizerState(INITIAL),
          tokenize: (line: string, state: TokenizerState) => {
            const res = grammar?.tokenizeLine(line, state.ruleStack)
            return {
              endState: new TokenizerState(res.ruleStack),
              tokens: res.tokens.map(token => {
                const lastScope = token.scopes[token.scopes.length - 1] as string
                return {
                  ...token,
                  scopes: editor ? TMToMonacoToken(editor, token.scopes) : lastScope,
                }
              }),
            }
          },
        })
      }
    }),
  )
}
