import type {Meta} from '@storybook/react'
import {Link} from './Link'
import {RoutesContext} from './routes-context'
import {jsonRoute} from './JsonRoute'
import {MemoryRouter} from 'react-router-dom'

const args = {
  to: '/home',
  children: 'Example Link',
}

const meta = {
  title: 'Utilities/Link',
  component: Link,
  tags: ['autodocs'],
  argTypes: {
    to: {
      description:
        'The path to link to. If the path is matched by React Router, a soft navigation will be executed. If the path is a Rails route, a Turbo navigation will be performed. If the path is external, the page will reload performing a hard navigation',
    },
    children: {
      description: 'The link text',
    },
  },
  decorators: [
    Story => (
      <RoutesContext.Provider
        value={{
          routes: [jsonRoute({path: '/home', Component: ({children}: React.PropsWithChildren) => <>{children}</>})],
        }}
      >
        <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
          <Story />
        </MemoryRouter>
      </RoutesContext.Provider>
    ),
  ],
} satisfies Meta<typeof Link>

export default meta

export const Example = {args}
