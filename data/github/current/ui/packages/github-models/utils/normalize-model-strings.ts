export const PUBLISHER = {
  Cohere: 'cohere',
  Core42: 'core42',
  DeepSeek: 'deepseek',
  Meta: 'meta',
  Microsoft: 'microsoft',
  Mistral: 'mistral',
  MistralAI: 'mistralai',
  MistralAI2: 'mistral ai',
  OpenAI: 'openai',
  OpenAIEVault: 'openaidevault',
  AI21Labs: 'ai21 labs',
  xAI: 'xai',
} as const

export type PUBLISHER = (typeof PUBLISHER)[keyof typeof PUBLISHER]

const KNOWN_PUBLISHERS: Record<string, string> = {
  cohere: 'Cohere',
  core42: 'Core42',
  deepseek: 'DeepSeek',
  meta: 'Meta',
  microsoft: 'Microsoft',
  mistral: 'Mistral',
  mistralai: 'Mistral',
  openai: 'Azure OpenAI Service',
  openaidevault: 'OpenAI',
  ai21labs: 'AI21 Labs',
  xai: 'xAI',
}

export function normalizeModelPublisher(publisher: string): string {
  const publisherLowercase = publisher.toLowerCase()
  return KNOWN_PUBLISHERS[publisherLowercase] || publisher
}
