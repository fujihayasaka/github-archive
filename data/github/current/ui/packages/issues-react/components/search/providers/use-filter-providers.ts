import {FILTER_KEYS, FILTER_PRIORITY_DISPLAY_THRESHOLD, type FilterProvider} from '@github-ui/filter'
import {
  ArchivedFilterProvider,
  BaseFilterProvider,
  ClosedFilterProvider,
  CommenterFilterProvider,
  CommentsFilterProvider,
  CreatedFilterProvider,
  DraftFilterProvider,
  HeadFilterProvider,
  InFilterProvider,
  InteractionsFilterProvider,
  IsFilterProvider,
  LabelFilterProvider,
  LanguageFilterProvider,
  LinkedFilterProvider,
  MentionsFilterProvider,
  MergedFilterProvider,
  MilestoneFilterProvider,
  OrgFilterProvider,
  ParentIssueFilterProvider,
  ProjectFilterProvider,
  ReactionsFilterProvider,
  ReasonFilterProvider,
  RepositoryFilterProvider,
  ReviewFilterProvider,
  ShaFilterProvider,
  SortFilterProvider,
  StateFilterProvider,
  StatusFilterProvider,
  TeamFilterProvider,
  TeamReviewRequestedFilterProvider,
  UpdatedFilterProvider,
  UserFilterProvider,
  UserReviewRequestedFilterProvider,
} from '@github-ui/filter/providers'
import {IS_FILTER_PROVIDER_NON_REPO_SCOPE_VALUES, IS_FILTER_PROVIDER_VALUES} from '../../../constants/values'
import {
  AssigneeFilterProviderWithCopilotSupport,
  AuthorFilterProviderWithCopilotSupport,
  InvolvesFilterProviderWithCopilotSupport,
  ReviewedByFilterProviderWithCopilotSupport,
  ReviewRequestedFilterProviderWithCopilotSupport,
} from './copilot-user'
import {IssueTypeFilterProvider} from '@github-ui/issue-type-filter-provider'
import {SubIssueFilterProvider} from './sub-issue'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../../types/app-payload'
import {useUser} from '@github-ui/use-user'
import {useEffect, useMemo} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {isTypeFilterProvider} from '../../../utils/type-predicates'

const conditionalProvider = (condition: boolean, provider: FilterProvider) => (condition ? [provider] : [])

type FilterProviderContext = {
  isOrgScope: boolean
}

export const useFilterProviders = (context: FilterProviderContext) => {
  const {isOrgScope = false} = context

  const {currentUser} = useUser()
  const relayEnvironment = useRelayEnvironment()
  const {scoped_repository} = useAppPayload<AppPayload>()

  const isRepoScope = !!scoped_repository
  const copilot_swe_agent = isFeatureEnabled('copilot_swe_agent')

  const providerRepositoryScope = isRepoScope ? `${scoped_repository.owner}/${scoped_repository.name}` : undefined
  const isFilterProviderValues = isRepoScope ? IS_FILTER_PROVIDER_VALUES : IS_FILTER_PROVIDER_NON_REPO_SCOPE_VALUES

  const providers: FilterProvider[] = useMemo(() => {
    const userFilterParam = {
      showAtMe: !!currentUser,
      currentUserLogin: currentUser?.login,
      currentUserAvatarUrl: currentUser?.avatarUrl,
      repositoryScope: providerRepositoryScope,
    }

    const noNoneValueFilterConfig = {filterTypes: {valueless: false}}
    const hasValueFilterConfig = {filterTypes: {hasValue: true}}

    return [
      ...conditionalProvider(
        !isRepoScope,
        new RepositoryFilterProvider({...noNoneValueFilterConfig, filterTypes: {multiKey: true}}),
      ),
      ...conditionalProvider(!isRepoScope, new OrgFilterProvider({...noNoneValueFilterConfig})),
      new IsFilterProvider(isFilterProviderValues, noNoneValueFilterConfig),
      new StateFilterProvider('mixed', noNoneValueFilterConfig),
      new LabelFilterProvider(hasValueFilterConfig),
      ...conditionalProvider(
        isOrgScope || !isRepoScope,
        new IssueTypeFilterProvider(
          hasValueFilterConfig,
          // legacy support for `type:issue` and `type:pr`
          true,
          relayEnvironment,
          providerRepositoryScope,
        ),
      ),
      new ProjectFilterProvider(hasValueFilterConfig),
      new MilestoneFilterProvider(hasValueFilterConfig),
      new AssigneeFilterProviderWithCopilotSupport(
        {...userFilterParam, showHasValue: true, showAtCopilot: copilot_swe_agent},
        hasValueFilterConfig,
      ),
      new AuthorFilterProviderWithCopilotSupport(
        {...userFilterParam, showAtCopilot: copilot_swe_agent},
        noNoneValueFilterConfig,
      ),
      new InvolvesFilterProviderWithCopilotSupport({...userFilterParam, showAtCopilot: true}, noNoneValueFilterConfig),
      new MentionsFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new ParentIssueFilterProvider(FILTER_KEYS.parentIssue, hasValueFilterConfig),
      new SubIssueFilterProvider(),
      new UpdatedFilterProvider(noNoneValueFilterConfig),
      new CreatedFilterProvider(noNoneValueFilterConfig),
      new ClosedFilterProvider(noNoneValueFilterConfig),
      new MergedFilterProvider(noNoneValueFilterConfig),
      new ReviewRequestedFilterProviderWithCopilotSupport(
        {...userFilterParam, showAtCopilot: true},
        noNoneValueFilterConfig,
      ),
      new InFilterProvider(),
      new CommenterFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new UserFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new UserReviewRequestedFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new ReviewedByFilterProviderWithCopilotSupport(
        {...userFilterParam, showAtCopilot: true},
        noNoneValueFilterConfig,
      ),
      new CommentsFilterProvider(noNoneValueFilterConfig),
      new InteractionsFilterProvider(noNoneValueFilterConfig),
      new ReasonFilterProvider(noNoneValueFilterConfig),
      new LinkedFilterProvider(['issue', 'pr'], noNoneValueFilterConfig),
      new ArchivedFilterProvider(noNoneValueFilterConfig),
      new ReactionsFilterProvider(noNoneValueFilterConfig),
      new DraftFilterProvider(noNoneValueFilterConfig),
      new ReviewFilterProvider(noNoneValueFilterConfig),
      new LanguageFilterProvider(noNoneValueFilterConfig),
      new ShaFilterProvider(noNoneValueFilterConfig),
      new BaseFilterProvider(noNoneValueFilterConfig),
      new HeadFilterProvider(noNoneValueFilterConfig),
      new StatusFilterProvider(noNoneValueFilterConfig),
      new TeamFilterProvider(providerRepositoryScope, noNoneValueFilterConfig),
      new TeamReviewRequestedFilterProvider(providerRepositoryScope, noNoneValueFilterConfig),
      new SortFilterProvider(['created', 'updated', 'reactions', 'comments', 'relevance'], noNoneValueFilterConfig),
    ]
  }, [
    copilot_swe_agent,
    currentUser,
    isFilterProviderValues,
    isOrgScope,
    providerRepositoryScope,
    relayEnvironment,
    isRepoScope,
  ])

  useEffect(() => {
    return () => {
      const typeFilterProvider = providers.find(isTypeFilterProvider)
      if (typeFilterProvider) {
        // Clean up cached issue type data from the store
        typeFilterProvider.requestDisposable?.dispose()
      }
    }
  }, [providers])

  // Currently, each provider sets its own priority. Sometimes this is something higher like 2 or 3 and
  // sometimes it's the default priorty of NOT_SHOWN (10). In the issues search context, we want to
  // show as many filters as possible, so we set all the priorities to FILTER_PRIORITY_DISPLAY_THRESHOLD
  // to ensure that they are shown. Instead of updating the configuration of each provider above, we
  // do it here and simply order the providers above in the way we want them shown.
  for (const provider of providers) {
    provider.priority = FILTER_PRIORITY_DISPLAY_THRESHOLD
  }

  return providers
}
