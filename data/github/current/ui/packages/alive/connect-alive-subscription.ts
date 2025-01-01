import type {Dispatchable, getSession} from './alive'
import {Topic, type Subscription} from '@github/alive-client'
import {taskQueue} from '@github-ui/eventloop-tasks'

type AliveSession = Exclude<Awaited<ReturnType<typeof getSession>>, undefined>
type Subscribable = Pick<AliveSession, 'subscribe' | 'unsubscribeAll'>

const sessionTaskQueues = new WeakMap<AliveSession, Subscribable>()

function getSessionTaskQueues(session: AliveSession): Subscribable {
  let queues = sessionTaskQueues.get(session)
  if (!queues) {
    queues = {
      subscribe: taskQueue<Array<Subscription<Dispatchable>>>(subs => session.subscribe(subs.flat())),
      unsubscribeAll: taskQueue<Dispatchable>(els => session.unsubscribeAll(...els)),
    }
    sessionTaskQueues.set(session, queues)
  }
  return queues
}

/**
 * Connect to an Alive subscription
 * @param aliveSession the Alive session
 * @param channelName the signed channel name
 * @param callback a callback to receive events from the alive channel. This callback should be memoized to avoid unnecessary resubscribes when React re-renders.
 */

export function connectAliveSubscription<T>(
  aliveSession: AliveSession | undefined,
  channelName: string | null,
  callback: (data: T) => unknown,
) {
  if (!aliveSession) {
    // the alive session failed to connect
    throw new Error('Not connected to alive')
  }

  if (!channelName) {
    throw new Error('No channel name')
  }

  const topic = Topic.parse(channelName)

  if (!topic) {
    throw new Error('Invalid channel name')
  }

  const aliveSubscription = {
    subscriber: {
      dispatchEvent: (event: Event) => {
        if (event instanceof CustomEvent) {
          const subscriptionEvent = event.detail
          callback(subscriptionEvent.data)
        }
      },
    },
    topic,
  }

  const subscriptionTarget = getSessionTaskQueues(aliveSession)
  subscriptionTarget.subscribe([aliveSubscription])
  return {
    unsubscribe: () => subscriptionTarget.unsubscribeAll(aliveSubscription.subscriber),
  }
}
