import {verifyPackageGenerator} from '../test-utils/verify-package-generator'
import {it, describe} from '@github-ui/tests'

describe('Basic package generator', () => {
  it('should generate a basic package without an entry', async () => {
    await verifyPackageGenerator({
      name: 'Basic Package',
      answers: {
        packageName: 'basic-package',
        packageDescription: 'A test basic package',
      },
      fixture: 'basic-package',
    })
  })
})
