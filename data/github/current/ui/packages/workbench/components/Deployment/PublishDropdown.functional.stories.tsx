import type {Meta} from '@storybook/react'

import {
  codespaceContextDecoratorArgs,
  codespaceContextDecoratorArgTypes,
  withCodespaceContext,
} from '../../contexts/.storybook/WithCodespaceContext'
import {
  IterationHistoryContextDecoratorArgs,
  IterationHistoryContextDecoratorArgTypes,
  withIterationHistoryContext,
} from '../../contexts/.storybook/WithIterationHistoryContext'
import {
  RoutePayloadDecoratorArgs,
  RoutePayloadDecoratorArgTypes,
  withRoutePayload,
} from '../../contexts/.storybook/WithRoutePayload'
import {
  terminalContextDecoratorArgs,
  terminalContextDecoratorArgTypes,
  withTerminalContext,
} from '../../contexts/.storybook/WithTerminalContext'
import {
  withWorkbenchContext,
  workbenchContextDecoratorArgs,
  workbenchContextDecoratorArgTypes,
} from '../../contexts/.storybook/WithWorkbenchContext'
import {PublishingProvider} from '../../contexts/PublishingContext'
import {PublishDropdown} from './PublishDropdown'

export default {
  title: 'Apps/Workbench/Components/Deployment/PublishDropdown/Functional',
  component: PublishDropdown,
  decorators: [
    withRoutePayload,
    withWorkbenchContext,
    withCodespaceContext,
    withTerminalContext,
    withIterationHistoryContext,
  ],
  argTypes: {
    variant: {},
    ...RoutePayloadDecoratorArgTypes,
    ...workbenchContextDecoratorArgTypes,
    ...codespaceContextDecoratorArgTypes,
    ...terminalContextDecoratorArgTypes,
    ...IterationHistoryContextDecoratorArgTypes,
  },
  args: {
    variant: 'button',
    ...RoutePayloadDecoratorArgs,
    ...workbenchContextDecoratorArgs,
    ...codespaceContextDecoratorArgs,
    ...terminalContextDecoratorArgs,
    ...IterationHistoryContextDecoratorArgs,
  },
  render: () => {
    return (
      <PublishingProvider>
        <PublishDropdown />
      </PublishingProvider>
    )
  },
} satisfies Meta<typeof PublishDropdown>

export const Default = {
  args: {
    deployExists: false,
  },
}
