import React, {createRef} from 'react'
import {mergeRefs} from '../merge-refs'
import {render, screen} from '@testing-library/react'

// Note this tests the "object" branch
test('it should allow merging', () => {
  const refA = createRef()
  const refB = createRef()
  const mergedRef = mergeRefs([refA, refB])

  mergedRef('hello')

  expect(refA.current).toBe('hello')
  expect(refB.current).toBe('hello')
})

// Note this tests the "function" branch
test('doesnt throw if a ref is null or undefined', () => {
  expect.assertions(2)

  // eslint-disable-next-line react/display-name
  const Component = React.forwardRef((props, ref) => {
    expect(ref).toBe(null)
    const internalRef = React.useRef(null)
    return <p ref={mergeRefs([ref, internalRef])}>body</p>
  })

  // Ref is null here, given not passed
  render(<Component />)
  expect(screen.getByText('body')).toBeInTheDocument()
})
