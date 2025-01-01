import type {Suggestion, Suggestions} from '@github-ui/inline-autocomplete/types'
import {ActionList} from '@primer/react'
import {useMemo} from 'react'

import {useChatState} from '../../utils/CopilotChatContext'
import {ReferenceMention} from '../../utils/reference-mention'
import {topLevelCategories} from './categories'
import {CategorySuggestion} from './CategorySuggestion'
import {DiscussionSuggestion} from './DiscussionSuggestion'
import {FileSuggestion} from './FileSuggestion'
import {IssueSuggestion} from './IssueSuggestion'
import {PullRequestSuggestion} from './PullRequestSuggestion'
import {RepositorySuggestion} from './RepositorySuggestion'

export interface CategoriesQuery {
  category: 'categories'
  filter: string
  index: number
}

function isAt(where: 'start' | 'anywhere', query: CategoriesQuery) {
  switch (where) {
    case 'start':
      return query.index === 0
    case 'anywhere':
      return true
  }
}

export function useCategoriesSuggestions(query: CategoriesQuery | null) {
  const {currentReferences} = useChatState()

  return useMemo<Suggestions | null>(() => {
    if (!query) return null

    const filterText = query.filter.toLowerCase()
    const filterMatches = (value: string) =>
      value.toLowerCase().includes(filterText) && value.toLowerCase() !== filterText

    const currentReferenceSuggestions = currentReferences
      .map((ref): Suggestion | null => {
        const mention = ReferenceMention.for(ref)

        switch (mention?.type) {
          case undefined:
            return null
          case 'repository': {
            const nwo = `${mention.reference.ownerLogin}/${mention.reference.name}`
            if (!filterMatches(nwo)) return null
            return {
              value: ReferenceMention.stringify(mention),
              render: props => (
                <RepositorySuggestion
                  repository={{
                    databaseId: mention.reference.id,
                    isInOrganization: mention.reference.ownerType === 'Organization',
                    name: mention.reference.name,
                    nwo,
                    ownerLogin: mention.reference.ownerLogin,
                  }}
                  {...props}
                />
              ),
            }
          }
          case 'issue': {
            const title = mention.reference.title ?? ''
            if (!filterMatches(title)) return null
            return {
              value: ReferenceMention.stringify(mention),
              render: props => (
                <IssueSuggestion
                  issue={{
                    number: mention.reference.number,
                    state: mention.reference.state ?? '',
                    title,
                  }}
                  {...props}
                />
              ),
            }
          }
          case 'pull-request': {
            const title = mention.reference.title ?? ''
            if (!filterMatches(title)) return null
            return {
              value: ReferenceMention.stringify(mention),
              render: props => (
                <PullRequestSuggestion
                  pullRequest={{
                    number: mention.reference.number,
                    state: mention.reference.state ?? '',
                    title,
                  }}
                  {...props}
                />
              ),
            }
          }
          case 'discussion': {
            const title = mention.reference.title ?? ''
            if (!filterMatches(title)) return null
            return {
              value: ReferenceMention.stringify(mention),
              render: props => (
                <DiscussionSuggestion
                  discussion={{
                    number: mention.reference.number,
                    state: mention.reference.state,
                    title,
                  }}
                  {...props}
                />
              ),
            }
          }
          case 'file': {
            const path = mention.reference.path
            if (!filterMatches(path)) return null
            return {
              value: ReferenceMention.stringify(mention),
              render: props => (
                <FileSuggestion type={mention.reference.type === 'folder' ? 'folder' : 'file'} path={path} {...props} />
              ),
            }
          }
        }
        return null
      })
      .filter(s => s !== null)

    const categorySuggestions = topLevelCategories
      .filter(category => category.name.toLowerCase().includes(filterText) && isAt(category.where, query))
      .map<Suggestion>(category => ({
        value: null,
        key: category.value,
        render: props => <CategorySuggestion category={category} {...props} />,
      }))

    // tack on a divider between the two lists
    if (categorySuggestions.length > 0) {
      const lastReferenceSuggestion = currentReferenceSuggestions.at(-1)
      if (lastReferenceSuggestion && typeof lastReferenceSuggestion === 'object') {
        const WithoutDivider = lastReferenceSuggestion.render
        lastReferenceSuggestion.render = props => (
          <>
            <WithoutDivider {...props} />
            <ActionList.Divider />
          </>
        )
      }
    }

    return currentReferenceSuggestions.concat(categorySuggestions)
  }, [query, currentReferences])
}
