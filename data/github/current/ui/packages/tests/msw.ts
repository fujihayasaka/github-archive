export {delay, http, HttpResponse} from 'msw'
export const msw =
  typeof window !== 'undefined' ? (await import('./msw-worker')).worker : (await import('./msw-node')).server
