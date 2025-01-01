import {verifyPackageGenerator} from '../test-utils/verify-package-generator'
import {it, describe} from '@github-ui/tests'

describe('React Data Router App generator', () => {
  it('should generate a React Data Router App', async () => {
    await verifyPackageGenerator({
      name: 'React App',
      answers: {
        packageName: 'test-react-data-router-app-package',
        packageDescription: 'A test React Data Router App package',
        routePath: '/some/:id/route',
        routeComponent: 'SomeRoute',
        enableSSR: false,
      },
      fixture: 'test-react-data-router-app-package',
    })
  })

  describe('with SSR enabled', () => {
    it('should generate a ssr-entry', async () => {
      await verifyPackageGenerator({
        name: 'React App',
        answers: {
          packageName: 'test-ssr-react-data-router-app-package',
          packageDescription: 'A test React Data Router App package',
          routePath: '/some/:id/route',
          routeComponent: 'SomeRoute',
          enableSSR: true,
        },
        fixture: 'test-ssr-react-data-router-app-package',
      })
    })
  })
})
