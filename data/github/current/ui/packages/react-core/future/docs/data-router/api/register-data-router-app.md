# `registerDataRouterApp`

📄 [`ui/packages/react-core/register-app.ts:18`](../../../../register-app.ts#L18)

Registers an app created with a [`DataRouterAppBuilder`](./data-router-application-builder.md) instance to be rendered.

```ts
import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {myExampleAppBuilder} from '../config/app-builder'

export const myExampleApp = myExampleAppBuilder.createDataRouterAppFromRoutes([])

registerDataRouterApp(myExampleApp)
```
