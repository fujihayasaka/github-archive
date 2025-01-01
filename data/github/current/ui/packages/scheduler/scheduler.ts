import {
  unstable_scheduleCallback as scheduleCallback,
  unstable_UserBlockingPriority as UserBlockingPriority,
  unstable_NormalPriority as NormalPriority,
  unstable_IdlePriority as IdlePriority,
} from 'scheduler'

const priorityLevels = {
  'user-blocking': UserBlockingPriority,
  'user-visible': NormalPriority,
  background: IdlePriority,
} as const

type Options = {
  /**
   * Scheduled callbacks run in {@link https://developer.mozilla.org/en-US/docs/Web/API/Prioritized_Task_Scheduling_API#task_priorities|priority} order when calling {@link postTask}.
   *
   * @default "user-visible"
   */
  priority?: keyof typeof priorityLevels
  signal?: AbortSignal
  delay?: number
}

/**
 * Schedules a callback to run in the future based on a given {@link https://developer.mozilla.org/en-US/docs/Web/API/Prioritized_Task_Scheduling_API#task_priorities|priority}.
 *
 * This exposes an API similar to {@link https://developer.mozilla.org/en-US/docs/Web/API/Scheduler/postTask|Scheduler: postTask()},
 * but it's not a shim or polyfill. Instead, it's a logical function that queues a callback based on priority.
 *
 * The {@link Options.priority|priority level} determines when the callback will be executed:
 * - `user-blocking`: Treated as "immediate"; executes within {@link https://github.com/facebook/react/blob/f739642745577a8e4dcb9753836ac3589b9c590a/packages/scheduler/src/forks/SchedulerFeatureFlags.www.js#L18|250ms} of being queued.
 * - `user-visible` (default): Executes at the next available opportunity, within {@link https://github.com/facebook/react/blob/f739642745577a8e4dcb9753836ac3589b9c590a/packages/scheduler/src/forks/SchedulerFeatureFlags.www.js#L19|5000ms}.
 * - `background`: Runs when the browser is idle, after higher-priority tasks have completed.
 */
export function postTask(callback: () => void, options?: Options) {
  let cb = callback

  if (options?.signal) {
    const signal = options.signal
    if (options?.signal?.aborted) return

    // scheduleCallback does not natively support abort signal's, so poor-mans approach, just wrap it
    cb = function signalCallback() {
      if (signal.aborted) return
      callback()
    }
  }

  scheduleCallback(priorityLevels[options?.priority || 'user-visible'], cb, {
    delay: options?.delay,
  })
}
