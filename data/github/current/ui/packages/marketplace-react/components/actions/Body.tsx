import {SafeHTMLBox} from '@github-ui/safe-html'
import {Blankslate} from '@primer/react/experimental'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {Contributors} from '../Contributors'
import {Resources} from './Resources'
import {ThirdPartyStatement} from './ThirdPartyStatement'
import {Stack} from '@primer/react'
import type {Repository} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'
import styles from '../../marketplace.module.css'

interface BodyProps {
  readmeHtml: SafeHTMLString
  helpUrl: string
  repository: Repository
  action: ActionListing
  repoAdminableByViewer: boolean
}

export function Body(props: BodyProps) {
  const {readmeHtml, helpUrl, repository, action, repoAdminableByViewer} = props

  return (
    <Stack gap="normal">
      {readmeHtml ? (
        <div data-testid="markdown-body" className={styles['marketplace-content-container']}>
          <SafeHTMLBox html={readmeHtml} className="markdown-body" />
        </div>
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
      <Stack className={'d-md-none'}>
        <Contributors repository={repository} />
        <Resources repository={repository} action={action} repoAdminableByViewer={repoAdminableByViewer} />
        <div className={'border-top color-border-muted pt-3'}>
          <ThirdPartyStatement isThirdParty={repository.isThirdParty} name={action.name} />
        </div>
      </Stack>
    </Stack>
  )
}
