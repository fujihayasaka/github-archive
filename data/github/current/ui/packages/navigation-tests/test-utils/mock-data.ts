import type {Payload} from '../types/payload'

export function getPayload({
  someField = 'someField',
  serverTime = '123',
}: {
  someField?: string
  serverTime?: string
} = {}): Payload {
  return {
    someField,
    serverTime,
  }
}
