import {Spinner} from '@primer/react'
import {useEffect, useState} from 'react'

/** More steps are smoother, but more expensive. */
const spinnerSteps = 20

/**
 * StateSpinner is an abomination that uses React state to manage the spin angle instead of a CSS animation. This
 * prevents the spin from being reset when the element tree changes but the component is not remounted, as happens
 * while streaming in content (the container for a given block is constantly a new element). The browser considers
 * this a remount and resets CSS animations.
 *
 * It's important that this is a small standalone component since it updates state many times per second.
 */
export function StateSpinner() {
  const [step, setStep] = useState(0)
  useEffect(() => {
    const interval = setInterval(() => setStep(s => (s + 1) % spinnerSteps), 1000 / spinnerSteps)
    return () => clearInterval(interval)
  }, [])

  return (
    <Spinner
      size="small"
      style={{
        animation: 'none',
        transform: `rotate(${(step / spinnerSteps) * 360}deg)`,
      }}
    />
  )
}
