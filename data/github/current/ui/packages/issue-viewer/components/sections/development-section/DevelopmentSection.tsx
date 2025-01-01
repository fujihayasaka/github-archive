import {PullRequestPickerFragment} from '@github-ui/item-picker/PullRequestPicker'
import type {
  PullRequestPickerPullRequest$data,
  PullRequestPickerPullRequest$key,
} from '@github-ui/item-picker/PullRequestPickerPullRequest.graphql'
import {ActionList, Box, Text} from '@primer/react'
import {useCallback, useMemo, useState} from 'react'
import {graphql, readInlineData, useFragment} from 'react-relay'

import {LABELS} from '../../../constants/labels'
import {TEST_IDS} from '../../../constants/test-ids'
import {VALUES} from '../../../constants/values'
import type {
  DevelopmentSectionFragment$data,
  DevelopmentSectionFragment$key,
} from './__generated__/DevelopmentSectionFragment.graphql'
import {LinkedPullRequests} from './LinkedPullRequests'
import {ReadonlySectionHeader} from '@github-ui/issue-metadata/ReadonlySectionHeader'
import {Section} from '@github-ui/issue-metadata/Section'
import {LazyDevelopmentPickerOnClick} from './DevelopmentPicker'
import {BranchPickerRefFragment} from '@github-ui/item-picker/BranchPicker'
import type {BranchPickerRef$data, BranchPickerRef$key} from '@github-ui/item-picker/BranchPickerRef.graphql'
import {LinkedBranches} from './LinkedBranches'
import {NoBranchesOrLinkedPullRequests} from './NoBranchesOrLinkedPullRequests'
import {BranchNextStepLocal} from './BranchNextStepLocal'
import type {BranchNextStep} from './CreateBranchDialog'

import {BranchNextStepDesktop} from './BranchNextStepDesktop'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {SectionHeader} from '@github-ui/issue-metadata/SectionHeader'

import {Banner} from '@primer/react/experimental'
import {useCopilotAgent} from '../../../hooks/use-copilot-agent'
import {CopilotAgentModeButton} from './CopilotAgentModeButton'

const developmentSectionFragment = graphql`
  fragment DevelopmentSectionFragment on Issue {
    repository {
      id
      databaseId
      name
      owner {
        login
      }
    }
    id
    title
    number
    databaseId
    linkedBranches(first: 25) {
      nodes {
        id
        ref {
          ...BranchPickerRef
        }
      }
    }
    closedByPullRequestsReferences(first: 10, includeClosedPrs: true) {
      nodes {
        ...PullRequestPickerPullRequest
      }
    }
    ...LinkedPullRequests
    viewerCanLinkBranches
  }
`

export const DevelopmentSectionReposGraphqlQuery = graphql`
  query DevelopmentSectionReposQuery($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      # eslint-disable-next-line relay/must-colocate-fragment-spreads This will be fixed on the item picker is refactored
      ...RepositoryPickerRepository
    }
    viewer {
      # eslint-disable-next-line relay/must-colocate-fragment-spreads This will be fixed on the item picker is refactored
      ...RepositoryPickerTopRepositories
    }
  }
`

export const DevelopmentSectionBranchesGraphqlQuery = graphql`
  query DevelopmentSectionBranchesQuery($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      ...BranchPickerRepositoryBranchRefs
    }
  }
`

export type DevelopmentSectionBaseProps = {
  onIssueUpdate?: () => void
}

type DevelopmentSectionInternalProps = DevelopmentSectionBaseProps & {
  issue: DevelopmentSectionFragment$key
}

export function DevelopmentSectionFallback() {
  return (
    <Section
      sectionHeader={<ReadonlySectionHeader title={LABELS.sectionTitles.development} />}
      emptyText={LABELS.emptySections.development}
    />
  )
}

export function DevelopmentSection({issue}: DevelopmentSectionInternalProps) {
  const [isCreateBranchDialogOpen, setCreateBranchDialogOpen] = useState(false)

  // TODO: use the `onIssueUpdate` callback once editing is implemented
  const data = useFragment(developmentSectionFragment, issue)
  const {id: issueId, title, number, databaseId, repository} = data
  const readonly = !data.viewerCanLinkBranches

  const [linkedBranches, linkedPullRequests] = useMemo(
    () => [getLinkedBranches(data), getLinkedPullRequests(data)],
    [data],
  )

  const hasSomeData = linkedBranches.length > 0 || linkedPullRequests.length > 0

  const [branchNextStep, setBranchNextStep] = useState<BranchNextStep>('none')
  const [newBranchName, setNewBranchName] = useState<string | null>(null)

  const noBranchesOrLinkedPullRequests = useCallback(
    (linkText: string, before?: string, after?: string) => {
      return (
        <NoBranchesOrLinkedPullRequests
          issueId={issueId}
          title={title}
          number={number}
          owner={repository.owner.login}
          repo={repository.name}
          before={before}
          after={after}
          linkText={linkText}
          reportCreateBranchDialogOpen={setCreateBranchDialogOpen}
          setBranchNextStep={setBranchNextStep}
          setNewBranchName={setNewBranchName}
        />
      )
    },
    [issueId, number, repository.name, repository.owner.login, title],
  )

  const developmentSectionHeader = useMemo(() => {
    if (readonly) {
      return <ReadonlySectionHeader title={LABELS.sectionTitles.development} />
    }

    return (
      <LazyDevelopmentPickerOnClick
        issueId={issueId}
        anchorElement={props => <SectionHeader title={LABELS.sectionTitles.development} buttonProps={props} />}
        repoPickerSubtitle={noBranchesOrLinkedPullRequests(
          LABELS.development.createBranch.toLowerCase(),
          LABELS.development.repoPickerSubtitle,
        )}
        prAndBranchPickerSubtitle={noBranchesOrLinkedPullRequests(
          LABELS.development.createBranch.toLowerCase(),
          LABELS.development.prsBranchesPickerSubtitle,
        )}
        isCreateBranchDialogOpen={isCreateBranchDialogOpen}
        linkedBranches={linkedBranches}
        linkedPullRequests={linkedPullRequests}
      />
    )
  }, [readonly, issueId, noBranchesOrLinkedPullRequests, isCreateBranchDialogOpen, linkedBranches, linkedPullRequests])

  const copilotAgentModeEnabled = useFeatureFlag('copilot_agent_mode')

  const {codespaceCreationError, setCodespaceCreationError} = useCopilotAgent({
    repoId: repository.id,
    issueDatabaseId: databaseId || 0,
  })

  return (
    <Section sectionHeader={developmentSectionHeader}>
      {copilotAgentModeEnabled && (
        // When the `copilot_agent_mode` feature flag is enabled,
        // display an "Open in Copilot Agent Mode" button that allows users
        // to open the current issue in a Codespace running Agent Mode.
        <Box sx={{px: 2, py: 2}}>
          <CopilotAgentModeButton repo={repository} issueId={databaseId ?? 0} onError={setCodespaceCreationError} />
          {codespaceCreationError && (
            <Banner
              title="Codespace creation failed"
              hideTitle
              description={LABELS.development.copilot.error(codespaceCreationError)}
              variant="critical"
              className="mt-2"
            />
          )}
        </Box>
      )}
      {!hasSomeData && (
        <Text sx={{fontSize: 0, px: 2, mb: 2, mt: 1, color: 'fg.muted', display: 'block'}}>
          {!readonly &&
            noBranchesOrLinkedPullRequests(
              LABELS.development.createBranch,
              undefined,
              LABELS.development.createBranchSuffix,
            )}
          <span>{readonly && LABELS.emptySections.development}</span>
        </Text>
      )}
      {branchNextStep === 'local' && (
        <BranchNextStepLocal branch={newBranchName} onClose={() => setBranchNextStep('none')} />
      )}
      {branchNextStep === 'desktop' && (
        <BranchNextStepDesktop
          owner={repository.owner.login}
          repository={repository.name}
          branch={newBranchName}
          onClose={() => setBranchNextStep('none')}
        />
      )}
      <ActionList variant={'full'} data-testid={TEST_IDS.linkedPullRequestContainer} sx={{overflowWrap: 'anywhere'}}>
        <LinkedBranches linkedBranches={linkedBranches} />
        <LinkedPullRequests linkedPullRequests={linkedPullRequests} />
      </ActionList>
    </Section>
  )
}

export type LinkedBranch = {
  name: string
  repositoryWithOwner: string
  repositoryId: string
  id: string
}

function getLinkedPullRequests(developmentData: DevelopmentSectionFragment$data): PullRequestPickerPullRequest$data[] {
  return (
    developmentData.closedByPullRequestsReferences?.nodes
      ?.flatMap(node => {
        if (!node) return []
        // eslint-disable-next-line no-restricted-syntax
        return readInlineData<PullRequestPickerPullRequest$key>(PullRequestPickerFragment, node)
      })
      .slice(0, VALUES.maxLinkedPullRequests) || []
  )
}

function getLinkedBranches(developmentData: DevelopmentSectionFragment$data): BranchPickerRef$data[] {
  return (
    developmentData.linkedBranches?.nodes
      ?.flatMap(node => {
        if (!node || !node.ref) return []
        // eslint-disable-next-line no-restricted-syntax
        return readInlineData<BranchPickerRef$key>(BranchPickerRefFragment, node.ref)
      })
      .slice(0, VALUES.maxLinkedBranches) || []
  )
}
