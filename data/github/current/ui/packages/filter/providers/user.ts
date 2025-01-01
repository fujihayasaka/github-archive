import {fuzzyScore, NO_MATCH} from '@github-ui/fuzzy-score/fuzzy-score'
import {ArrowSwitchIcon, PlusCircleIcon} from '@primer/octicons-react'
import {hasMatch} from 'fzy.js'

import {INDETERMINANT, USER_FILTERS} from '../constants/filter-constants'
import type {FilterQuery} from '../filter-query'
import {
  type AnyBlock,
  type ARIAFilterSuggestion,
  AvatarType,
  type FilterConfig,
  type FilterKey,
  type FilterProvider,
  FilterProviderType,
  type FilterValueData,
  FilterValueType,
  type IndexedBlockValueItem,
  type MutableFilterBlock,
  type SuppliedFilterProviderOptions,
  type ValueRowProps,
} from '../types'
import {getFilterValue, getLastFilterBlockValue, getUnescapedFilterValue, isFilterBlock} from '../utils'
import {ValueIcon} from '../utils/ValueIcon'
import {AsyncFilterProvider} from './async'

const USER_SUGGESTION_ENDPOINT = '/_filter/users'
const USER_VALIDATION_ENDPOINT = '/_filter/users/validate'
const AT_ME_VALUE = '@me'

const AT_ME_SUGGESTION = {
  type: FilterValueType.Value,
  value: AT_ME_VALUE,
  ariaLabel: `${AT_ME_VALUE}, Signed-in user`,
  displayName: 'Me',
  description: 'Signed-in user',
  inlineDescription: true,
  priority: 1,
  icon: ArrowSwitchIcon,
  iconColor: 'var(--fgColor-done, var(--color-done-fg))',
}

const WILDCARD_HAS_VALUE = '*'
const getHasValueSuggestion = (displayName: string) => ({
  type: FilterValueType.Value,
  value: WILDCARD_HAS_VALUE,
  displayName: `Has ${displayName.toLocaleLowerCase()}`,
  ariaLabel: `Has ${displayName}, ${displayName}`,
  priority: 1,
  icon: PlusCircleIcon,
})

export type User = {
  name: string
  login: string
  avatarUrl?: string
}

export type UserFilterParams = {
  showAtMe?: boolean
  showHasValue?: boolean
  currentUserLogin?: string
  currentUserAvatarUrl?: string
  repositoryScope?: string
  includeBots?: boolean
}

export class BaseUserFilterProvider extends AsyncFilterProvider<User> implements FilterProvider {
  showAtMe: boolean
  showHasValue: boolean
  currentUserLogin?: string
  currentUserAvatarUrl?: string
  includeBots?: boolean

  constructor(filterParams: UserFilterParams, filterKey: FilterKey, options?: SuppliedFilterProviderOptions) {
    super(filterKey, options)
    this.suggestionEndpoint = USER_SUGGESTION_ENDPOINT
    this.validationEndpoint = USER_VALIDATION_ENDPOINT
    this.currentUserLogin = filterParams.currentUserLogin
    this.currentUserAvatarUrl = filterParams.currentUserAvatarUrl
    this.includeBots = filterParams.includeBots ?? false
    this.type = FilterProviderType.User
    this.showAtMe = filterParams?.showAtMe ?? true
    this.showHasValue = filterParams?.showHasValue ?? false
  }

  async getSuggestions(
    filterQuery: FilterQuery,
    filterBlock: AnyBlock | MutableFilterBlock,
    config: FilterConfig,
    caretIndex?: number | null,
  ) {
    if (this.includeBots) {
      filterQuery.addQueryParam('include_bots', '1')
    }
    const suggestions =
      (await this.processSuggestions(filterQuery, filterBlock, this.processSuggestion.bind(this), caretIndex)) ?? []
    const lastValue = getLastFilterBlockValue(filterBlock, caretIndex)
    const hasNoValueRow = suggestions[0]?.type === FilterValueType.NoValue
    let spliceIndex = hasNoValueRow ? 1 : 0
    if (
      this.showAtMe &&
      (lastValue === '' || hasMatch(lastValue, AT_ME_VALUE)) &&
      isFilterBlock(filterBlock) &&
      filterBlock.value?.values.findIndex(v => v.value === AT_ME_VALUE) < 0
    ) {
      suggestions.splice(spliceIndex, 0, AT_ME_SUGGESTION)
      spliceIndex++
    }
    if (
      this.showHasValue &&
      (lastValue === '' || hasMatch(lastValue, WILDCARD_HAS_VALUE)) &&
      isFilterBlock(filterBlock) &&
      filterBlock.value?.values.findIndex(v => v.value === WILDCARD_HAS_VALUE) < 0
    ) {
      suggestions.splice(spliceIndex, 0, getHasValueSuggestion(this.displayName))
    }
    return suggestions
  }

  private processSuggestion(user: User, query: string): ARIAFilterSuggestion {
    const {login, name, avatarUrl} = user
    let priority = 3

    if (query) {
      // Weight the score more heavily by login, then influence by name
      const loginWeighting = 0.75
      if (login) {
        const loginScore = fuzzyScore(query, login)
        priority -= (loginScore !== NO_MATCH ? loginScore : 1) * loginWeighting
      }

      if (name) {
        const nameScore = fuzzyScore(query, name)
        priority -= (nameScore !== NO_MATCH ? nameScore : 1) * (1 - loginWeighting)
      }
    }

    // We want to have @me at the top if it's included
    if (login === AT_ME_VALUE) {
      priority = 1
    }

    return {
      type: FilterValueType.Value,
      value: login,
      ariaLabel: `${login}, ${name}, ${this.displayName}`,
      description: name,
      inlineDescription: true,
      priority,
      icon: !avatarUrl ? this.icon : undefined,
      avatar: avatarUrl ? {url: avatarUrl, type: AvatarType.User} : undefined,
    }
  }

  override getMetaSuggestions(value: string): ARIAFilterSuggestion[] {
    const suggestions: ARIAFilterSuggestion[] = []
    if (this.showAtMe && AT_ME_VALUE.startsWith(value)) {
      suggestions.push(AT_ME_SUGGESTION)
    }
    if (this.showHasValue && WILDCARD_HAS_VALUE.startsWith(value)) {
      suggestions.push(getHasValueSuggestion(this.displayName))
    }

    return suggestions
  }

  override validateValue(
    filterQuery: FilterQuery,
    value: IndexedBlockValueItem,
    user: User | null,
  ): false | Partial<IndexedBlockValueItem> | null | undefined {
    const extractedValue = getUnescapedFilterValue(value.value)

    if (extractedValue === AT_ME_VALUE) {
      return {
        avatar: this.currentUserAvatarUrl ? {url: this.currentUserAvatarUrl, type: AvatarType.User} : undefined,
        value: extractedValue,
      }
    }
    if (this.showHasValue && extractedValue === WILDCARD_HAS_VALUE) {
      return {
        avatar: undefined,
        value: extractedValue,
      }
    }

    if (user && extractedValue)
      return {
        avatar: user.avatarUrl ? {url: user.avatarUrl, type: AvatarType.User} : undefined,
        value: extractedValue,
        displayName: user.name,
      }

    if (!filterQuery.context.repo && !filterQuery.context.org) {
      return {
        value: INDETERMINANT,
      }
    }

    return false
  }

  getValueRowProps(value: FilterValueData): ValueRowProps {
    return {
      text: value.displayName ?? getFilterValue(value.value) ?? '',
      description: value.description,
      descriptionVariant: 'inline',
      leadingVisual: ValueIcon({value, providerIcon: this.icon}),
    }
  }
}

export class AssigneeFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.assignee, options)
  }
}

export class AuthorFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    const defaultOptions: SuppliedFilterProviderOptions = {filterTypes: {multiValue: false, valueless: false}}
    super(
      {
        ...filterParams,
        includeBots: true,
      },
      USER_FILTERS.author,
      {
        ...defaultOptions,
        ...options,
        filterTypes: {...defaultOptions.filterTypes, ...options?.filterTypes},
      },
    )
  }
}

export class CommenterFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.commenter, options)
  }
}

export class InvolvesFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.involves, options)
  }
}

export class MentionsFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.mentions, options)
  }
}

export class ReviewedByFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.reviewedBy, options)
  }
}

export class ReviewRequestedFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.reviewRequested, options)
  }
}

export class UserFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.user, options)
  }
}

export class UserReviewRequestedFilterProvider extends BaseUserFilterProvider {
  constructor(filterParams: UserFilterParams, options?: SuppliedFilterProviderOptions) {
    super(filterParams, USER_FILTERS.userReviewRequested, options)
  }
}
