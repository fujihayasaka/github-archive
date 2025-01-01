import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {repoModelsPath, modelsCatalogPath} from '@github-ui/paths'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {
  CommandPaletteIcon,
  HomeIcon,
  NoteIcon,
  AppsIcon,
  SidebarExpandIcon,
  ArrowUpRightIcon,
  GitCompareIcon,
} from '@primer/octicons-react'
import {Heading, IconButton, Label, NavList, PageLayout, type PageLayoutContentProps} from '@primer/react'
import type {PropsWithChildren} from 'react'
import {Link, useMatch, useResolvedPath, useLocation} from 'react-router-dom'
import type {ModelRepoPayload} from '../types'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {PaidUsageBanner} from '@github-ui/github-models/PaidUsageBanner'
import styles from './ModelsRepoLayout.module.css'
import {aboutGitHubModelsDocsUrl} from '../constants'
import {clsx} from 'clsx'

function NavItem({
  to,
  children,
  icon,
  trailingIcon,
}: {
  to: string
  children: React.ReactNode
  icon: React.ReactNode
  trailingIcon?: React.ReactNode
}) {
  const resolved = useResolvedPath(to)
  let isCurrent = !!useMatch({path: resolved.pathname, end: true})

  const currentPath = useLocation().pathname

  // Special case for playground route since `models/playground` redirects to `models/:publisher/:modelName/playground`
  if (to.endsWith('/playground')) {
    const playgroundPathRegex = /^\/[^/]+\/[^/]+\/models\/[^/]+\/[^/]+\/playground$/ // Matches `/:owner/:repo/models/:publisher/:modelName/playground`
    isCurrent = playgroundPathRegex.test(currentPath)
  }

  return (
    <NavList.Item href={to} aria-current={isCurrent ? 'page' : undefined}>
      <NavList.LeadingVisual>{icon}</NavList.LeadingVisual>
      {children}
      {trailingIcon ? <NavList.TrailingVisual>{trailingIcon}</NavList.TrailingVisual> : null}
    </NavList.Item>
  )
}

export function ModelsRepoLayout({
  children,
  fileTreeExpanded,
  setFileTreeExpanded,
  width = 'large' as const,
}: PropsWithChildren<{
  fileTreeExpanded: boolean
  setFileTreeExpanded: (expanded: boolean) => void
  width?: PageLayoutContentProps['width']
}>) {
  const {repository, canEdit, paidUsageBannerDismissed, businessSlug} = useAppPayload<ModelRepoPayload>()
  const showPlaygroundNavItem = useFeatureFlag('github_models_repo_playground') && canEdit
  const showComparisonsNavItem = useFeatureFlag('github_models_repo_comparisons')

  return (
    <CurrentRepositoryProvider repository={repository}>
      <PageLayout containerWidth="full" columnGap="none" padding="none">
        {fileTreeExpanded && (
          <PageLayout.Pane
            padding="condensed"
            position="start"
            hidden={{
              narrow: true,
              regular: false,
              wide: false,
            }}
            divider="line"
            sticky
          >
            <div className="d-flex flex-column height-full pl-3 pt-3">
              <div className="d-flex flex-justify-between">
                <Heading as="h2" className="f3" id="pane-heading">
                  Models
                </Heading>
                <IconButton
                  onClick={() => setFileTreeExpanded(false)}
                  aria-label="Collapse menu"
                  icon={SidebarExpandIcon}
                  variant="invisible"
                />
              </div>
              <NavList className="flex-1">
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
                  icon={<NoteIcon />}
                >
                  Prompts
                </NavItem>
                {showComparisonsNavItem && (
                  <NavItem
                    to={repoModelsPath({
                      repo: repository,
                      action: 'comparisons',
                    })}
                    icon={<GitCompareIcon />}
                  >
                    Comparisons
                  </NavItem>
                )}
                {showPlaygroundNavItem && (
                  <NavItem
                    to={repoModelsPath({
                      repo: repository,
                      action: 'playground',
                    })}
                    icon={<CommandPaletteIcon />}
                  >
                    Playground
                  </NavItem>
                )}
                <NavList.Divider />
                <NavItem to={modelsCatalogPath()} icon={<AppsIcon />} trailingIcon={<ArrowUpRightIcon />}>
                  Catalog
                </NavItem>
              </NavList>
              <div className="d-flex flex-justify-between my-2">
                <div>
                  <Link to={aboutGitHubModelsDocsUrl}>Docs</Link>
                  <span className="mx-1">·</span>
                  <Link to="https://github.com/orgs/community/discussions/categories/models">Share feedback</Link>
                </div>
                <Label variant="success">Public Preview</Label>
              </div>
            </div>
          </PageLayout.Pane>
        )}
        <PageLayout.Content
          className={clsx(styles.content, 'fill-page-height')}
          padding="condensed"
          width={width}
          as="section"
        >
          <PaidUsageBanner
            dismissed={paidUsageBannerDismissed}
            repository={repository}
            businessSlug={businessSlug}
            className="mb-2"
          />
          {children}
        </PageLayout.Content>
      </PageLayout>
    </CurrentRepositoryProvider>
  )
}
