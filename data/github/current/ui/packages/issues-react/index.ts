import ISSUE_VIEWER_VIEW_QUERY from '@github-ui/issue-viewer/IssueViewerViewQuery.graphql'
import ISSUE_VIEWER_SECONDARY_VIEW_QUERY from '@github-ui/issue-viewer/IssueViewerSecondaryViewQuery.graphql'
import ISSUE_INDEX_SECONDARY_QUERY from '@github-ui/list-view-items-issues-prs/IssuesIndexSecondaryQuery'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'

import {relayRoute} from '@github-ui/relay-route'

import {App} from './App'
import CUSTOM_VIEWS_QUERY from './components/sidebar/__generated__/SavedViewsQuery.graphql'
import {clientSideRelayDataGenerator, setRecordMap} from './pages/ClientSideRelayDataGenerator'
import {IssueDashboardCustomViewPage} from './pages/IssueDashboardCustomViewPage'
import {IssueDashboardKnownViewPage} from './pages/IssueDashboardKnownViewPage'
import {IssueDashboardPage} from './pages/IssueDashboardPage'
import {IssueIndexPage} from './pages/IssueIndexPage'
import {IssueShowPage} from './pages/IssueShowPage'
import CURRENT_VIEW_QUERY from './pages/__generated__/ClientSideRelayDataGeneratorViewQuery.graphql'
import ISSUE_DASHBOARD_CUSTOM_VIEW_PAGE_QUERY from './pages/__generated__/IssueDashboardCustomViewPageQuery.graphql'
import ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY from './pages/__generated__/IssueDashboardKnownViewPageQuery.graphql'
import ISSUE_INDEX_PAGE_QUERY from './pages/__generated__/IssueIndexPageQuery.graphql'
import REPOSITORY_MILESTONE_PAGE_QUERY from './pages/__generated__/RepositoryMilestonePageQuery.graphql'
import REPOSITORY_MILESTONE_INDEX_PAGE_QUERY from './pages/__generated__/RepositoryMilestoneIndexPageQuery.graphql'
import REPOSITORY_MILESTONE_NEW_PAGE_QUERY from './pages/milestone-new/__generated__/RepositoryMilestoneNewPageQuery.graphql'
import REPOSITORY_MILESTONE_EDIT_PAGE_QUERY from './pages/milestone-edit/__generated__/RepositoryMilestoneEditPageQuery.graphql'
import ISSUE_DASHBOARD_INDEX_PAGE_QUERY from './pages/__generated__/IssueDashboardPageQuery.graphql'
import REPOSITORY_LABEL_INDEX_PAGE_QUERY from './pages/__generated__/RepositoryLabelIndexPageQuery.graphql'
import {IssueRepoNewPage} from './pages/issue-new/IssueRepoNewPage'
import URL_ARGUMENTS_METADATA_QUERY from './pages/issue-new/__generated__/InternalIssueNewPageUrlArgumentsMetadataQuery.graphql'
import {VARIABLE_TRANSFORMERS} from './utils/variable-transformers'
import type {ErrorCallbacks} from '@github-ui/fetch-graphql'
import USE_ISSUE_FILTERING_QUERY from '@github-ui/item-picker/useIssueFilteringQuery.graphql'
import {IssueRepoNewChoosePage} from './pages/issue-new/IssueRepoNewChoosePage'
import ISSUE_NEW_CHOOSE_QUERY from './pages/issue-new/__generated__/IssueRepoNewChoosePageQuery.graphql'
import {RepositoryMilestonePage} from './pages/RepositoryMilestonePage'
import {RepositoryMilestoneIndexPage} from './pages/RepositoryMilestoneIndexPage'
import {RepositoryMilestoneNewPage} from './pages/milestone-new/RepositoryMilestoneNewPage'
import {RepositoryLabelIndexPage} from './pages/RepositoryLabelIndexPage'
import {RepositoryMilestoneEditPage} from './pages/milestone-edit/RepositoryMilestoneEditPage'

const isDevelopment = () => process.env.NODE_ENV === 'development'

// queries whose SAML errors we are ignoring as the errors are expected
const allowedQueries = [
  USE_ISSUE_FILTERING_QUERY.params.name,
  ISSUE_VIEWER_SECONDARY_VIEW_QUERY.params.name,
  ISSUE_INDEX_SECONDARY_QUERY.params.name,
]

const handleForbiddenError = (params?: {persistedQueryName: string; errorMessage: string}) => {
  if (
    params?.persistedQueryName &&
    allowedQueries.includes(params?.persistedQueryName) &&
    params.errorMessage === 'SAML error'
  ) {
    /*
      Ignore error if persisted query is among allowed queries and it's a SAML error.
      This is because these errors are expected.
      We should revisit this implementation after this issue is resolved: https://github.com/github/issues/issues/12095
    */
    return
  }

  reloadPage()
}

const reloadPage = () => {
  const reloadParameter = ['reload', '1'] as const
  const url = new URL(window.location.href, window.location.origin)

  /**
   * Return early when the parameter already exists to avoid an infinite loop
   */
  if (url.searchParams.has(...reloadParameter)) {
    return
  }

  url.searchParams.set(...reloadParameter)
  // Reload the page
  window.location.assign(url)
}

registerNavigatorApp('issues-react', () => {
  const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()
  setRecordMap(relayEnvironment)
  clientSideRelayDataGenerator({environment: relayEnvironment})

  const errorCallbacks: ErrorCallbacks = {
    404: {
      // handle authentication error
      AUTHENTICATION: reloadPage,
    },
    200: {
      // handle SAML error
      FORBIDDEN: handleForbiddenError,
    },
  }

  const relayRouteConfig = {
    componentLoader: async () => {
      throw new Error('This method should not be called')
    },
    fallback: isDevelopment() ? 'Loading...' : '',
    relayEnvironment,
  }
  return {
    App,
    routes: [
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:name/issues/new',
        resourceName: 'IssueRepoNew',
        title: 'New Issue',
        Component: IssueRepoNewPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:name/issues/new'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: URL_ARGUMENTS_METADATA_QUERY,
            variableMappers: routeParams => {
              return {
                owner: routeParams.pathParams['owner'],
                name: routeParams.pathParams['name'],
              }
            },
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:name/issues/new/choose',
        resourceName: 'IssueRepoNewChoose',
        title: 'Choose an Issue Template',
        Component: IssueRepoNewChoosePage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:name/issues/new/choose'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_NEW_CHOOSE_QUERY,
            variableMappers: routeParams => {
              return {
                owner: routeParams.pathParams['owner'],
                name: routeParams.pathParams['name'],
              }
            },
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/issues/assigned',
        resourceName: 'ClientSideView',
        title: 'Assigned to me',
        Component: IssueDashboardKnownViewPage,
        transitionType: 'transition-while-fetch',
        transformVariables: VARIABLE_TRANSFORMERS['/issues/assigned'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY,
          },
          customViewsQuery: {
            concreteRequest: CUSTOM_VIEWS_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/issues/mentioned',
        resourceName: 'ClientSideView',
        title: 'Mentioned',
        Component: IssueDashboardKnownViewPage,
        transitionType: 'transition-while-fetch',
        transformVariables: VARIABLE_TRANSFORMERS['/issues/mentioned'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY,
          },
          customViewsQuery: {
            concreteRequest: CUSTOM_VIEWS_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/issues/created',
        resourceName: 'ClientSideView',
        title: 'Created by me',
        Component: IssueDashboardKnownViewPage,
        transitionType: 'transition-while-fetch',
        transformVariables: VARIABLE_TRANSFORMERS['/issues/created'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY,
          },
          customViewsQuery: {
            concreteRequest: CUSTOM_VIEWS_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/issues/recent',
        resourceName: 'ClientSideView',
        title: 'Recent Activity',
        Component: IssueDashboardKnownViewPage,
        transitionType: 'transition-while-fetch',
        transformVariables: VARIABLE_TRANSFORMERS['/issues/recent'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY,
          },
          customViewsQuery: {
            concreteRequest: CUSTOM_VIEWS_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/issues/:number',
        resourceName: 'IssueShow',
        title: 'Issue',
        Component: IssueShowPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/issues/:number'],
        queryConfigs: {
          issueViewerViewQuery: {
            concreteRequest: ISSUE_VIEWER_VIEW_QUERY,
            variableMappers: routeParams => {
              return {
                owner: routeParams.pathParams['owner'],
                repo: routeParams.pathParams['repo'],
                number: routeParams.pathParams['number'] ? parseInt(routeParams.pathParams['number']) : undefined,
              }
            },
          },
        },
        maxAge: 10,
        errorCallbacks,
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/issues',
        resourceName: 'IssueRepoIndex',
        title: 'Repo Issues',
        Component: IssueIndexPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/issues'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_INDEX_PAGE_QUERY,
          },
        },
        errorCallbacks,
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/issues/:id',
        resourceName: 'View',
        title: 'View',
        Component: IssueDashboardCustomViewPage,
        transitionType: 'transition-while-fetch',
        transformVariables: VARIABLE_TRANSFORMERS['/issues/:id'],
        queryConfigs: {
          currentViewQuery: {
            concreteRequest: CURRENT_VIEW_QUERY,
            variableMappers: routeParams => {
              return {
                id: routeParams.pathParams['id'],
              }
            },
          },
          pageQuery: {
            concreteRequest: ISSUE_DASHBOARD_CUSTOM_VIEW_PAGE_QUERY,
          },
          customViewsQuery: {
            concreteRequest: CUSTOM_VIEWS_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/issues',
        resourceName: 'IssuesIndex',
        title: 'Issues',
        Component: IssueDashboardPage,
        transformVariables: VARIABLE_TRANSFORMERS['/issues'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_DASHBOARD_INDEX_PAGE_QUERY,
          },
          customViewsQuery: {
            concreteRequest: CUSTOM_VIEWS_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/issues/created_by/:author',
        resourceName: 'IssueRepoIndex',
        title: 'Repo Issues',
        Component: IssueIndexPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/issues/created_by/:author'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_INDEX_PAGE_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/issues/created_by/app/:author',
        resourceName: 'IssueRepoIndex',
        title: 'Repo Issues',
        Component: IssueIndexPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/issues/created_by/app/:author'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_INDEX_PAGE_QUERY,
          },
        },
      }),

      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/issues/assigned/:assignee',
        resourceName: 'IssueRepoIndex',
        title: 'Repo Issues',
        Component: IssueIndexPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/issues/assigned/:assignee'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_INDEX_PAGE_QUERY,
          },
        },
      }),

      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/milestone/:number',
        resourceName: 'RepoMilestoneShow',
        title: '', // Milestone-based title is set in the component; This should be empty otherwise NavigatorClientEntry.tsx undoes the dynamic title.
        // Document title will never be empty in practice since we have the Github fallback should the component not set it.
        Component: RepositoryMilestonePage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/milestone/:number'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: REPOSITORY_MILESTONE_PAGE_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/milestones',
        resourceName: 'RepoMilestoneIndex',
        title: 'Milestone Index',
        Component: RepositoryMilestoneIndexPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/milestones'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: REPOSITORY_MILESTONE_INDEX_PAGE_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/milestones/new',
        resourceName: 'RepoMilestoneNew',
        title: 'New Milestone',
        Component: RepositoryMilestoneNewPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/milestones/new'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: REPOSITORY_MILESTONE_NEW_PAGE_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/milestones/:number/edit',
        resourceName: 'RepoMilestoneEdit',
        title: 'Edit Milestone',
        Component: RepositoryMilestoneEditPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/milestones/:number/edit'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: REPOSITORY_MILESTONE_EDIT_PAGE_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/labels',
        resourceName: 'RepoLabelsIndex',
        title: 'Labels Index',
        Component: RepositoryLabelIndexPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/labels'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: REPOSITORY_LABEL_INDEX_PAGE_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/issues/labels',
        resourceName: 'RepoLabelsIndex',
        title: 'Labels Index',
        Component: RepositoryLabelIndexPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/labels'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: REPOSITORY_LABEL_INDEX_PAGE_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/issues/mentioned/:mentioned',
        resourceName: 'IssueRepoIndex',
        title: 'Repo Issues',
        Component: IssueIndexPage,
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/issues/mentioned/:mentioned'],
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_INDEX_PAGE_QUERY,
          },
        },
      }),
      relayRoute({
        ...relayRouteConfig,
        path: '/:owner/:repo/labels/:label',
        transformVariables: VARIABLE_TRANSFORMERS['/:owner/:repo/labels/:label'],
        resourceName: 'IssueLabelIndex',
        title: 'Label Issues',
        Component: IssueIndexPage,
        queryConfigs: {
          pageQuery: {
            concreteRequest: ISSUE_INDEX_PAGE_QUERY,
          },
        },
      }),
    ],
  }
})
