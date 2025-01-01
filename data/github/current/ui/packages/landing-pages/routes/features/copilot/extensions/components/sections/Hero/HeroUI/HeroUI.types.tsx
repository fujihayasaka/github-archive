export const validExtensions = ['docker', 'mermaidchart', 'models', 'perplexityai', 'sentry'] as const
export type Extension = (typeof validExtensions)[number]
