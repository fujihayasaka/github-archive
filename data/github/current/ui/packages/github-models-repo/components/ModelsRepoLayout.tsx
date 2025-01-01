import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {repoModelsPath} from '@github-ui/paths'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {CommentDiscussionIcon, HomeIcon} from '@primer/octicons-react'
import {Heading, NavList, PageLayout} from '@primer/react'
import type {PropsWithChildren} from 'react'
import {useMatch, useResolvedPath} from 'react-router-dom'
import type {ModelRepoPayload} from '../types'

function NavItem({to, children, icon}: {to: string; children: React.ReactNode; icon: React.ReactNode}) {
  const resolved = useResolvedPath(to)
  const isCurrent = useMatch({path: resolved.pathname, end: true})
  return (
    <NavList.Item href={to} aria-current={isCurrent ? 'page' : undefined}>
      <NavList.LeadingVisual>{icon}</NavList.LeadingVisual>
      {children}
    </NavList.Item>
  )
}

export function ModelsRepoLayout({children}: PropsWithChildren) {
  const {repository} = useAppPayload<ModelRepoPayload>()

  return (
    <CurrentRepositoryProvider repository={repository}>
      <PageLayout containerWidth="full">
        <PageLayout.Pane
          position="start"
          hidden={{
            narrow: true,
            regular: false,
            wide: false,
          }}
          divider="line"
        >
          <Heading as="h2" className="f3" id="pane-heading">
            Models
          </Heading>
          <NavList>
            <NavItem
              to={repoModelsPath({
                repo: repository,
                action: '',
              })}
              icon={<HomeIcon />}
            >
              Overview
            </NavItem>
            <NavItem
              to={repoModelsPath({
                repo: repository,
                action: 'prompts',
              })}
              icon={<CommentDiscussionIcon />}
            >
              Prompts
            </NavItem>
          </NavList>
        </PageLayout.Pane>
        <PageLayout.Content as="div">{children}</PageLayout.Content>
      </PageLayout>
    </CurrentRepositoryProvider>
  )
}
