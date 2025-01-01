import type {Icon} from '@primer/octicons-react'
import {NumberIcon, TypographyIcon, CheckIcon, ListUnorderedIcon, FileIcon} from '@primer/octicons-react'
import type {InputType, TextNode} from './app'

/**
 * Information and metadata about input types
 */
export interface InputTypeInfo {
  name: string
  description: string
  icon: Icon
}

/**
 * Display info and metadata about input types
 */
export const inputTypeInfo: Record<InputType['type'], InputTypeInfo> = {
  range: {
    name: 'Range',
    description: 'A numeric value within a specified range',
    icon: NumberIcon,
  },
  text: {
    name: 'Text',
    description: 'Free form text input',
    icon: TypographyIcon,
  },
  boolean: {
    name: 'Boolean',
    description: 'True or false value',
    icon: CheckIcon,
  },
  select: {
    name: 'Select',
    description: 'Choose from a list of predefined options',
    icon: ListUnorderedIcon,
  },
  file: {
    name: 'File',
    description: 'Upload and reference a file',
    icon: FileIcon,
  },
}

/**
 * Helper function to get a field from InputTypeInfo for a text node's input type
 */
export function getInputNodeTypeField<K extends keyof InputTypeInfo>(node: TextNode, field: K): InputTypeInfo[K] {
  const inputType = node.inputType.type
  const info = inputTypeInfo[inputType] ?? inputTypeInfo['text']
  return info[field]
}
