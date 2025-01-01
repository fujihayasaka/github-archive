import type {TagStyle} from '@codemirror/language'
import {tags as t} from '@lezer/highlight'

// these keys should be lower cased versions of LanguageDescription.name
type LanguageThemeMapping = {
  [key: string]: TagStyle[]
}

// This is a mapping of language names to the tags that should be highlighted for that language
const languageThemes: LanguageThemeMapping = {
  ruby: [
    {
      tag: t.variableName,
      color: 'var(--codeMirror-syntax-fgColor-variable, var(--color-codemirror-syntax-variable))',
    },
  ],
  html: [
    {
      tag: t.meta,
      color: 'var(--color-prettylights-syntax-constant)',
    },
    {
      tag: t.name,
      color: 'var(--color-prettylights-syntax-entity-tag)',
    },
  ],
  javascript: [
    {
      tag: t.name,
      color: 'var(--color-prettylights-syntax-variable)',
    },
  ],
  typescript: [
    {
      tag: t.name,
      color: 'var(--color-prettylights-syntax-variable)',
    },
    {
      tag: t.typeName,
      color: 'var(--color-prettylights-syntax-keyword)',
    },
  ],
  java: [
    {
      tag: t.typeName,
      color: 'var(--color-prettylights-syntax-entity)',
    },
  ],
  'c++': [
    {
      tag: t.meta,
      color: 'var(--color-prettylights-syntax-constant)',
    },
    {
      tag: t.typeName,
      color: 'var(--color-prettylights-syntax-keyword)',
    },
  ],
  php: [
    {
      tag: t.processingInstruction,
      color: 'var(--color-prettylights-syntax-constant)',
    },
    {
      tag: t.name,
      color: 'var(--color-prettylights-syntax-entity)',
    },
  ],
}

export const languageNames = Object.keys(languageThemes)

export function loadLanguageTheme(name: string) {
  if (languageNames.includes(name.toLowerCase())) {
    return languageThemes[name.toLowerCase()]
  }

  return null
}
