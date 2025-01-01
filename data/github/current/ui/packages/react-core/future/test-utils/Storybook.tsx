import type {Meta, StoryContext, StoryFn, StoryObj} from '@storybook/react'
import type {ComponentProps, JSXElementConstructor} from 'react'

import type {EmbeddedData} from '../../embedded-data-types'
import type {DataRouterApplication} from '../data-router-application'
import {createMemoryDataRouter, DataRouterAppWrapper, type PathOrRouterOptions} from './DataRouterAppWrapper'

/**
 * Returns a [storybook decorator](https://storybook.js.org/docs/writing-stories/decorators) that wraps the story in
 * the `react-core/future/test-utils/Wrapper` for use with DataRouter applications.
 *
 * @example
 * ```tsx
 * import {
 *   dataRouterDecorator,
 *   type DataRouterMeta,
 *   type DataRouterStoryObj,
 * } from '@github-ui/react-core/future/test-utils/storybook'
 * import {MyRouteComponent} from './routes/MyRouteComponent'
 * import {myRoute} from './routes/my-route'
 * import {myAppBuilder} from './my-app-builder'
 * import {myApp} from './my-app-builder'
 *
 * // define the story Meta
 * export default {
 *  title: 'Apps/My App',
 *  component: MyRouteComponent,
 *  // wrap every story in the decorators defined on the Meta.
 *  decorators: [dataRouterDecorator],
 * // provide parameters such as initialEntries or embeddedData to the decorator
 *   parameters: {
 *     dataRouter: {
 *      // You must provide an `app` that is either a `DataRouterApplication` or a function that returns one.
 *      // this can be a real app such as the one rendered by your package entry point,
 *      // or you can construct a custom app that renders the `Story` so that you use storybook APIs like `args` etc.
 *       app: myApp,
 *       // The initial route that is rendered, The default is ['/']
 *       initialEntries: [myRoute.generatePath({})],
 *     }
 *   },
 *   // You must mock any requests for your route's queries using msw
 *   msw: {
 *     handlers: [
 *       http.get(myRoute.generatePath({}), () => HttpResponse.json({someField: 'Some Data'})),
 *    ],
 *   },
 * } satisfies DataRouterMeta<typeof MyComponent>
 *
 * // This story will use the default parameters defined on the `meta`
 * export const Example: DataRouterStoryObj<typeof MyComponent> = {}
 *
 * // This story overrides the meta on an individual story via `parameters.dataRouter`
 * export const OtherExample: DataRouterStoryObj<typeof MyComponent> = {parameters: {dataRouter: {initialEntries: '/shawarma'}}}
 *
 * // This story uses the `app` function to create a new app for the story
 * // It sets up a new decorator rather than using the one that's rendered on the `meta`
 * export const OneOffExample: DataRouterStoryObj<typeof MyComponent> = {
 *   decorators: [dataRouterDecorator]
 *   parameters: {
 *    dataRouter: {
        app: (Story, context) => appBuilder.createDataRouterAppFromRoutes([
 *        myRoute.toRoute({Component: () => <Story />}),
 *      ]),
 *      initialEntries: [myRoute.generatePath({})],
 *    }
 *  },
 * }
 * ```
 */

export function dataRouterDecorator<TComponent extends AnyJSXElementConstructor>(
  Story: StoryFn,
  context: StoryContext<ComponentProps<TComponent>> & {parameters: DataRouterStoryObj<TComponent>['parameters']},
) {
  const {app, initialEntries = '/', embeddedData, appPayload} = context.parameters.dataRouter ?? {}
  if (!app || typeof app === 'undefined') {
    throw new Error('`dataRouterDecorator` requires that a `parameters.dataRouter.app` be defined')
  }
  const resolvedApp = typeof app === 'function' ? app(Story, context) : app
  const router = createMemoryDataRouter({app: resolvedApp, initialEntries, embeddedData, appPayload})
  return <DataRouterAppWrapper app={resolvedApp} router={router} />
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyJSXElementConstructor = JSXElementConstructor<any>

export type DataRouterParameters<TComponent extends AnyJSXElementConstructor> = {
  app?:
    | DataRouterApplication<string>
    | ((story: StoryFn, context: StoryContext<ComponentProps<TComponent>>) => DataRouterApplication<string>)
  initialEntries?: PathOrRouterOptions
  embeddedData?: EmbeddedData
  appPayload?: Record<string, unknown>
}

export type DataRouterMeta<TComponent extends AnyJSXElementConstructor> = Meta<TComponent> & {
  component: TComponent
  decorators: [typeof dataRouterDecorator<TComponent>]
  parameters: {
    dataRouter: DataRouterParameters<TComponent> & {
      app: NonNullable<DataRouterParameters<TComponent>['app']>
    }
  }
}

export type DataRouterStoryObj<TComponent extends AnyJSXElementConstructor> = StoryObj<TComponent> & {
  parameters?: {
    dataRouter?: DataRouterParameters<TComponent>
  }
}
