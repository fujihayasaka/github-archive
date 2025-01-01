import type {Meta} from '@storybook/react'
import {HttpResponse, http} from 'msw'
import {RefSelectorPartial} from './RefSelectorPartial'
import {getRefSelectorPartialProps, getRefsResponse} from './test-utils/mock-data'
import type {RefType} from '@github-ui/ref-selector'

const args = getRefSelectorPartialProps()

const meta = {
  title: 'Utilities/RefSelectorPartial',
  component: RefSelectorPartial,
} satisfies Meta<typeof RefSelectorPartial>

export default meta

export const Example = {
  args,
  parameters: {
    msw: {
      handlers: [
        http.get(`/${args.ownerLogin}/${args.repoName}/refs`, ({request}) => {
          const type = (new URL(request.url, window.location.origin).searchParams.get('type') as RefType) ?? 'branch'
          return HttpResponse.json(getRefsResponse(type))
        }),
      ],
    },
  },
}

export const LoadingError = {
  args,
  parameters: {
    msw: {
      handlers: [http.get(`/${args.ownerLogin}/${args.repoName}/refs`, () => new Response(null, {status: 404}))],
    },
  },
}
