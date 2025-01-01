/** @jest-environment node */
// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {it, expect, vi} from '@github-ui/tests'
import {renderToString} from 'react-dom/server'
import {useLayoutEffect} from '../use-layout-effect'
import {useState} from 'react'

const Component = () => {
  const [state, setState] = useState('')
  useLayoutEffect(() => {
    setState('ran effect')
  }, [])
  return <div>{state}</div>
}
it('Renders the useIsomorphicLayoutEffect hook', async () => {
  const error = vi.spyOn(console, 'error').mockImplementation(() => {})
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
  const log = vi.spyOn(console, 'log').mockImplementation(() => {})
  expect(() => {
    renderToString(<Component />)
  }).not.toThrow()

  expect(error).not.toHaveBeenCalled()
  expect(warn).not.toHaveBeenCalled()
  expect(log).not.toHaveBeenCalled()
})
