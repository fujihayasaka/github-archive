import {expect, it} from '@github-ui/tests'
import {whatever} from '../basic-package'

it('basic-package', () => {
  expect(whatever).toBe('replace me')
})
