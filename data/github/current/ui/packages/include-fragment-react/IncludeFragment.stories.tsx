import type {Meta} from '@storybook/react'
import {IncludeFragment, type IncludeFragmentProps} from './IncludeFragment'
import {http, HttpResponse} from 'msw'

function wait(n: number) {
  return new Promise(function (resolve) {
    return setTimeout(resolve, n)
  })
}

const meta = {
  title: 'Recipes/IncludeFragment',
  component: IncludeFragment,
  parameters: {
    msw: {
      handlers: [
        http.get('/deferred', async () => {
          await wait(2000)
          // eslint-disable-next-line github/unescaped-html-literal
          return HttpResponse.html('<h1>Include Fragment</h1>')
        }),
      ],
    },
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof IncludeFragment>

export default meta

const defaultArgs: Partial<IncludeFragmentProps> = {
  src: '/deferred',
}

export const IncludeFragmentExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: IncludeFragmentProps) => <IncludeFragment {...args}>Loading...</IncludeFragment>,
}
