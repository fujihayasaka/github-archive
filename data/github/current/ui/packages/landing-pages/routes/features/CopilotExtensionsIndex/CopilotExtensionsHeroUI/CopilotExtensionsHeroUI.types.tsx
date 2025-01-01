export const validExtensions = ['azure', 'datastax', 'docker', 'mongodb', 'sentry'] as const
export type Extension = (typeof validExtensions)[number]
