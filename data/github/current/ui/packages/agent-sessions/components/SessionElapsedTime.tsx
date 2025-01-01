import {useEffect, useState} from 'react'
import {calculateElapsedTime} from '../utils/elapsed-time-util'
import {SessionState} from '../types/session'

function SessionElapsedTime({
  createdAt,
  completedAt,
  state,
}: {
  createdAt: Date | string
  completedAt?: Date | string
  state: SessionState
}) {
  // Use useEffect to update the elapsed time when props change
  const [elapsedTime, setElapsedTime] = useState<string>(() => calculateElapsedTime(createdAt, completedAt))

  // Calculate initial elapsed time and update when props change
  useEffect(() => {
    setElapsedTime(calculateElapsedTime(createdAt, completedAt))

    if (state === SessionState.InProgress) {
      const interval = setInterval(() => {
        setElapsedTime(calculateElapsedTime(createdAt, completedAt))
      }, 500)
      return () => clearInterval(interval)
    }
  }, [createdAt, completedAt, state])
  return <time aria-live="off">{elapsedTime}</time>
}

export default SessionElapsedTime
