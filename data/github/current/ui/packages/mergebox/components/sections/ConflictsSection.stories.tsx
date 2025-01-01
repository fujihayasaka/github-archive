import type {Meta, StoryObj} from '@storybook/react'
import {MemoryRouter} from 'react-router-dom'

import {ConflictsSection, type ConflictsSectionProps} from './ConflictsSection'
import {RoutesContext} from '@github-ui/react-core/routes-context'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {
  conflictsSectionAdminDisabled,
  conflictsSectionCleanMergeState,
  conflictsSectionComplexConflictsMergeState,
  conflictsSectionHasRebaseConflicts,
  conflictsSectionHeadBranchProtected,
  conflictsSectionInsufficientAccessToResolve,
  conflictsSectionPendingMergeState,
  conflictsSectionStandardConflictsMergeState,
} from '../../test-utils/mocks/conflicts-condition-mock'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {http, HttpResponse} from 'msw'

const conflictsSectionDefaultProps: ConflictsSectionProps = {
  ...conflictsSectionCleanMergeState,
  baseRefName: 'main',
  headRefOid: 'abc123',
  resourcePath: '/octocat/Hello-World/pull/123',
  viewerCanUpdateBranch: true,
  viewerLogin: 'monalisa',
  canUserPushToBase: true,
  advisoryWorkspace: null,
  conflictsState: 'NO_CONFLICTS',
  viewerUpdateMethods: [
    {
      allowableStatus: 'ALLOWED',
      name: 'MERGE',
      failureReason: null,
      isDefault: true,
    },
    {
      allowableStatus: 'ALLOWED',
      name: 'REBASE',
      failureReason: null,
      isDefault: false,
    },
  ],
}

const updatePullRequestBranchRoute = `${BASE_PAGE_DATA_URL}/page_data/update_pull_request_branch`
const orchestrationUrl = 'https://github.com/orchestration/1234'

const meta: Meta<ConflictsSectionProps> = {
  title: 'Pull Requests/Merge Box/ConflictsSection',
  component: ConflictsSection,
  decorators: [
    Story => (
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <RoutesContext.Provider
          value={{
            routes: [jsonRoute({path: '/a', Component: () => null})],
          }}
        >
          <div style={{maxWidth: '600px'}}>
            <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
              <Story />
            </PageDataContextProvider>
          </div>
        </RoutesContext.Provider>
      </MemoryRouter>
    ),
  ],
  parameters: {
    msw: {
      handlers: [
        http.post(updatePullRequestBranchRoute, () => {
          return HttpResponse.json({orchestration: {url: orchestrationUrl}}, {status: 200})
        }),
        http.get(orchestrationUrl, () => {
          return HttpResponse.json({orchestration: {}}, {status: 200})
        }),
      ],
    },
  },
  args: conflictsSectionDefaultProps,
}

type Story = StoryObj<ConflictsSectionProps>

export const ConflictsSectionCleanStory: Story = {
  render: args => {
    const props = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionPendingStory: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionPendingMergeState,
      conflictsState: 'PENDING',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionHasConflictsStory: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionStandardConflictsMergeState,
      conflictsState: 'HAS_CONFLICTS',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionComplexConflictsStory: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionComplexConflictsMergeState,
      conflictsState: 'HAS_CONFLICTS',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionInsufficientAccessStory: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionInsufficientAccessToResolve,
      conflictsState: 'HAS_CONFLICTS',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionHeadBranchProtectedStory: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionHeadBranchProtected,
      conflictsState: 'HAS_CONFLICTS',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionAdminDisabledStory: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionAdminDisabled,
      conflictsState: 'HAS_CONFLICTS',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionRebaseConflictStory: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionHasRebaseConflicts,
      conflictsState: 'HAS_REBASE_CONFLICTS',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionCleanStoryUpdateBranchError: Story = {
  parameters: {
    msw: {
      handlers: [
        http.post(updatePullRequestBranchRoute, () => {
          return HttpResponse.json({orchestration: {url: orchestrationUrl}}, {status: 200})
        }),
        http.get(orchestrationUrl, () => {
          return HttpResponse.json({orchestration: {error_message: 'Trouble updating branch'}}, {status: 200})
        }),
      ],
    },
  },
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
      conflictsState: 'OUT_OF_DATE',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionCleanStoryUpdateBranchRequestFailed: Story = {
  parameters: {
    msw: {
      handlers: [
        http.post(updatePullRequestBranchRoute, () => {
          return HttpResponse.json({error: 'Branch update already in progress'}, {status: 422})
        }),
      ],
    },
  },
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
      conflictsState: 'OUT_OF_DATE',
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionAdvisoryWorkspacePresent: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
      conflictsState: 'HAS_ADVISORY_WORKSPACE',
      advisoryWorkspace: {
        advisoryWorkspacePath: 'smile/monalisa/security/advisory/123',
        advisoryWorkspaceId: '123',
      },
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionOnlyOneUpdateMethod: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
      viewerUpdateMethods: [
        {
          allowableStatus: 'ALLOWED',
          name: 'MERGE',
          failureReason: null,
          isDefault: true,
        },
        {
          allowableStatus: 'BLOCKED',
          name: 'REBASE',
          failureReason: null,
          isDefault: false,
        },
      ],
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionRebaseUnavailable: Story = {
  render: args => {
    const props: ConflictsSectionProps = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
      viewerUpdateMethods: [
        {
          allowableStatus: 'ALLOWED',
          name: 'MERGE',
          failureReason: null,
          isDefault: true,
        },
        {
          allowableStatus: 'UNAVAILABLE',
          name: 'REBASE',
          failureReason: 'There was a problem generating the rebase commit.',
          isDefault: false,
        },
      ],
    }
    return <ConflictsSection {...props} />
  },
}

export default meta
