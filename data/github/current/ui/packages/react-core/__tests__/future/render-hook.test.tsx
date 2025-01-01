// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useMatches} from 'react-router-dom'
import {renderHook} from '../../future/test-utils/Render'

function useMyHook() {
  return useMatches()
}

describe('RenderHook', () => {
  test('renders a hook inside the necessary providers', () => {
    const {result} = renderHook(useMyHook, '/')

    expect(result.current).toEqual([
      expect.objectContaining({
        id: '0',
        pathname: '/',
      }),
      expect.objectContaining({
        id: '0-0',
        pathname: '/',
      }),
      expect.objectContaining({
        id: '0-0-0',
        pathname: '/',
      }),
    ])
  })
})
