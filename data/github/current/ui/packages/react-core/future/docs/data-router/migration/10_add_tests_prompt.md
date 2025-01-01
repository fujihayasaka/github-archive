# Migration Step: Add Tests for Routes

- **You should review the example commits shown below to understand the testing patterns for data router applications.**
- For every migration, before adding tests:
  - **Important: Only ADD new tests. DO NOT modify or delete any existing tests in the codebase.**
  - **Review the example commits to understand the proper testing structure.**
  - Review your migrated routes to determine what tests are needed.
  - Ensure you have suitable mock data for testing each route.
  - **If Jest is missing dependencies, install them:** `npm install -D jest @types/jest jest-environment-jsdom @testing-library/react @testing-library/jest-dom`
  - **If you're using payload types in tests, import them from your extracted payload types file** (e.g., `../types/payloads.ts`) to prevent circular dependencies.
  - For each route in your migrated application:
    - Create a test file in the `__tests__` directory named after the route component (e.g., `YourRouteComponent.test.tsx`)
    - Create a corresponding SSR test file with the same name plus "SSR" (e.g., `YourRouteComponentSSR.test.tsx`)
    - Add the `/** @jest-environment node */` directive at the top of SSR test files
    - Build a mock payload that matches the route's expected data structure
    - For CSR tests: Use the `render` utility to render the app with the payload and assert that key UI elements are present
    - For SSR tests: Use the `serverRenderReact` utility with the app's SSR entry point and assert that the rendered HTML contains expected content
  - **Do not add extra code, comments, or examples beyond what is necessary for testing.**
  - **Ensure proper file formatting:**
    - All files must end with exactly one newline
    - No trailing whitespace
    - Proper comma usage in imports and object literals
    - Run the appropriate eslint command (see starting instructions) to automatically fix most formatting issues
  - Before making any changes, summarize what tests you will add for each route.
- **Be sure to review the example commits linked at the bottom of this prompt for reference implementations.**
- **After adding tests, run the appropriate lint and test commands (see starting instructions):**

## Example Implementation

Below is an example pattern to follow for your tests:

```typescript
// CSR test for your route
import {getYourRouteMockPayload} from '../test-utils/mock-data'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {yourApp} from '../your-app'
import {screen} from '@testing-library/react'

describe('your route', () => {
  it('renders with CSR from embedded data', async () => {
    // Important: use the exact same route key as in your routes file
    const payload = {yourRouteKey: getYourRouteMockPayload()}
    render(yourApp, '/route/path', {
      embeddedData: {
        payload,
        meta: {
          title: 'Your Route Title',
        },
      },
    })

    expect(await screen.findByText('Expected Text From Payload')).toBeInTheDocument()
  })
})
```

```typescript
// SSR test for your route
/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../ssr-entry'
import {getYourRouteMockPayload} from '../test-utils/mock-data'

describe('your route', () => {
  it('renders with SSR', async () => {
    // Important: use the exact same route key as in your routes file
    const payload = {yourRouteKey: getYourRouteMockPayload()}

    const view = await serverRenderReact({
      name: 'your-app',
      path: '/route/path',
      data: {payload},
      data_router_enabled: true,
    })

    // Verify SSR was able to render some content from the payload
    expect(view).toMatch('Expected Text From Payload')
  })
})
```

```typescript
// Mock data helper for your test
// Import your payload types from the shared types file to prevent circular dependencies
import type {YourRoutePayload} from '../types/payloads'

export function getYourRouteMockPayload(): YourRoutePayload {
  return {
    property1: 'value1',
    property2: true,
    items: [
      { id: 1, name: 'Expected Text From Payload' }
    ]
  }
}
```

## Reference Commits

- **Verify that all routes in your migrated application have corresponding tests.**
- **Ensure all tests pass before completing the migration process.**
- **Remember: Only add new tests for your migrated routes. DO NOT modify or remove existing tests.**
- **For reference implementation patterns, see this example commit:**
  - [add_client_tests.diff](add_client_tests.diff): Example tests for client routes