import {SafeHTMLBox} from '@github-ui/safe-html'
import {Blankslate} from '@primer/react/experimental'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {Contributors} from '../Contributors'
import {Resources} from './Resources'
import {ThirdPartyStatement} from './ThirdPartyStatement'
import {Stack, Box} from '@primer/react'
import type {Repository} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'

interface BodyProps {
  readmeHtml: SafeHTMLString
  helpUrl: string
  repository: Repository
  action: ActionListing
}

export function Body(props: BodyProps) {
  const {readmeHtml, helpUrl, repository, action} = props

  return (
    <>
      {readmeHtml ? (
        <Box
          data-testid="markdown-body"
          className={'width-full border rounded-2 color-shadow-small'}
          sx={{p: [2, 2, 3]}}
        >
          <SafeHTMLBox html={readmeHtml} className="markdown-body p-3" />
        </Box>
      ) : (
        <Blankslate spacious>
          <Blankslate.Heading>No description</Blankslate.Heading>
          <Blankslate.Description>
            This GitHub Action has no README in the repository. If{' '}
            <a className="Link--inTextBlock" href={helpUrl}>
              one is added
            </a>
            , it will appear here.
          </Blankslate.Description>
        </Blankslate>
      )}
      <Stack className={'mt-3 d-md-none'}>
        <Contributors repository={repository} />
        <Resources repository={repository} action={action} />
        <div className={'border-top color-border-muted pt-3'}>
          <ThirdPartyStatement isThirdParty={repository.isThirdParty} name={action.name} />
        </div>
      </Stack>
    </>
  )
}
