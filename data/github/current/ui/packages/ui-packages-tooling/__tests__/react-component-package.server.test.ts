import {verifyPackageGenerator} from '../test-utils/verify-package-generator'
import {it, describe} from '@github-ui/tests'

describe('React Component generator', () => {
  it('should generate a React Component', async () => {
    await verifyPackageGenerator({
      name: 'React Component',
      answers: {
        packageName: 'test-react-component-package',
        packageDescription: 'A test React Component package',
      },
      fixture: 'test-react-component-package',
    })
  })
})
