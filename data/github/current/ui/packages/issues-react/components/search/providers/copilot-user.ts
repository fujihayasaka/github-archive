import {
  type FilterKey,
  type SuppliedFilterProviderOptions,
  type FilterQuery,
  type AnyBlock,
  type MutableFilterBlock,
  type FilterConfig,
  USER_FILTERS,
  type ARIAFilterSuggestion,
  FilterValueType,
  AvatarType,
} from '@github-ui/filter'
import {
  AT_COPILOT_VALUE,
  BaseUserFilterProvider,
  type User as FilterProviderUser,
  type UserFilterParams,
} from '@github-ui/filter/providers'
import {CopilotIcon} from '@primer/octicons-react'

type User = {
  isCopilot?: boolean
} & FilterProviderUser

const getCopilotSuggestion = (displayName: string, avatarUrl: string | undefined) => ({
  type: FilterValueType.Value,
  value: AT_COPILOT_VALUE,
  ariaLabel: `${AT_COPILOT_VALUE}, Your AI pair programmer`,
  displayName,
  description: 'Your AI pair programmer',
  inlineDescription: true,
  priority: 1,
  icon: CopilotIcon,
  avatarUrl: avatarUrl ? {url: avatarUrl, type: AvatarType.User} : undefined,
  iconColor: 'var(--fgColor-done, var(--color-done-fg))',
})

class CopilotUserFilterProvider extends BaseUserFilterProvider {
  copilotQueryParamKey?:
    | 'show_assignee_copilot'
    | 'show_author_copilot'
    | 'show_pull_request_reviewer_copilot'
    | 'show_involves_copilot'

  constructor(filterParams: UserFilterParams, filterKey: FilterKey, options?: SuppliedFilterProviderOptions) {
    super(filterParams, filterKey, options)
  }

  override async getSuggestions(
    filterQuery: FilterQuery,
    filterBlock: AnyBlock | MutableFilterBlock,
    config: FilterConfig,
    caretIndex?: number | null,
  ) {
    if (this.copilotQueryParamKey) {
      filterQuery.addQueryParam(this.copilotQueryParamKey, '1')
    }

    return super.getSuggestions(filterQuery, filterBlock, config, caretIndex)
  }

  override validateFilterValue(
    value: string,
    fetchParams?: URLSearchParams,
    filterQuery?: FilterQuery,
  ): Promise<User | Error | null> {
    const params = new URLSearchParams(fetchParams)
    if (this.copilotQueryParamKey) {
      params.append(this.copilotQueryParamKey, '1')
    }
    return super.validateFilterValue(value, params, filterQuery)
  }

  protected override processSuggestion(user: User, query: string): ARIAFilterSuggestion {
    const {login, avatarUrl, isCopilot} = user

    if (isCopilot) {
      return getCopilotSuggestion(login, avatarUrl)
    }

    return super.processSuggestion(user, query)
  }
}

export class AssigneeFilterProviderWithCopilotSupport extends CopilotUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.assignee, options)
    this.copilotQueryParamKey = filterParams.showAtCopilot ? 'show_assignee_copilot' : undefined
  }
}

export class AuthorFilterProviderWithCopilotSupport extends CopilotUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.author, options)
    this.copilotQueryParamKey = filterParams.showAtCopilot ? 'show_author_copilot' : undefined
  }
}

export class ReviewedByFilterProviderWithCopilotSupport extends CopilotUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.reviewedBy, options)
    this.copilotQueryParamKey = filterParams.showAtCopilot ? 'show_pull_request_reviewer_copilot' : undefined
  }
}

export class ReviewRequestedFilterProviderWithCopilotSupport extends CopilotUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.reviewRequested, options)
    this.copilotQueryParamKey = filterParams.showAtCopilot ? 'show_pull_request_reviewer_copilot' : undefined
  }
}

export class InvolvesFilterProviderWithCopilotSupport extends CopilotUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.involves, options)
    this.copilotQueryParamKey = filterParams.showAtCopilot ? 'show_involves_copilot' : undefined
  }
}
