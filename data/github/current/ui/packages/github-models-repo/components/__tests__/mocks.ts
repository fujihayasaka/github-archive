import type {ParsedPrompt} from '../../types'
import {promptModelIdentifierFor} from '../../routes/prompt/models'
import {mockModel} from '../../test-utils/mock-data'

export const mockPrompt = (name: string): ParsedPrompt => ({
  name,
  description: `A description of ${name}`,
  path: `prompts/${name.toLowerCase().replace(/\s/g, '-')}.prompt.yml`,
  model: promptModelIdentifierFor(mockModel()),
})

export const mockPrompts = (count = 5): ParsedPrompt[] =>
  Array.from({length: count}, (_, i) => mockPrompt(`Prompt ${i + 1}`))
