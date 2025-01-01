// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {act, fireEvent, render, screen} from '@testing-library/react'
import {useEffect, useState} from 'react'

import useSafeState from '../use-safe-state'

describe('useSafeState()', () => {
  let states: Array<[boolean, boolean]>

  beforeEach(() => {
    jest.useFakeTimers()
    states = []
  })

  const Child = () => {
    const [loading, setLoading] = useSafeState(true)

    useEffect(() => {
      const timeout = window.setTimeout(
        () =>
          setLoading((previous: boolean) => {
            states.push([previous, false])
            return false
          }),
        100,
      )

      return () => {
        window.clearTimeout(timeout)
      }
    }, [setLoading])

    return <div>Loading? {loading}</div>
  }

  const Parent = () => {
    const [showChild, setShowChild] = useState(true)

    return (
      <>
        <button onClick={() => setShowChild(current => !current)}>Toggle</button>
        {showChild && <Child />}
      </>
    )
  }

  it('sets state in a mounted component', () => {
    render(<Parent />)

    expect(states).toEqual([])

    act(() => {
      jest.runAllTimers()
    })

    expect(states).toEqual([[true, false]])
  })

  it('is a harmless no-op in an unmounted component', () => {
    render(<Parent />)

    expect(states).toEqual([])

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByText('Toggle'))

    expect(states).toEqual([])

    jest.runAllTimers()

    expect(states).toEqual([])
  })
})
