import {findSortReactionInQuery, getQuery, replaceDateTokens} from '@github-ui/list-view-items-issues-prs/Query'
import type {VariableTransformer} from '@github-ui/relay-route/types'
import {REPOSITORY_VIEW, CUSTOM_VIEW} from '../constants/view-constants'
import {addPagingParams, parseValidProjectNumbersFromUrlParameter} from './urls'
import {QUERIES} from '@github-ui/query-builder/constants/queries'
import {VALUES} from '@github-ui/repository-milestone/values'
import {CONSTS} from '@github-ui/repository-label/values'

export const variablesIndex: VariableTransformer<string> = (variables, routeParams) => {
  const newVariables = variables
  if (Object.keys(routeParams.pathParams).length > 0) {
    const urlQuery = routeParams.searchParams.get('q')

    const defaultQuery = `${urlQuery || REPOSITORY_VIEW.query}`

    const customQuery = CUSTOM_VIEW.query({
      author: routeParams.pathParams['author'],
      assignee: routeParams.pathParams['assignee'],
      mentioned: routeParams.pathParams['mentioned'],
      label: routeParams.pathParams['label'],
    })

    newVariables['query'] = getQuery(customQuery && !urlQuery ? `${defaultQuery} ${customQuery}` : defaultQuery, {
      owner: routeParams.pathParams['owner']!,
      name: routeParams.pathParams['repo']!,
    })

    addPagingParams(routeParams.searchParams, newVariables)

    newVariables['owner'] = routeParams.pathParams['owner']!
    newVariables['name'] = routeParams.pathParams['repo']!
    newVariables['includeReactions'] = urlQuery ? findSortReactionInQuery(urlQuery) : false
  }

  return newVariables
}

function createVariableTransformers<const T extends Record<string, VariableTransformer<string>>>(transformers: T) {
  return transformers
}
export const VARIABLE_TRANSFORMERS = createVariableTransformers({
  '/:owner/:name/issues/new': (variables, routeParams) => {
    const newVariables = variables

    const assignees = routeParams.searchParams.get('assignees')
    if (assignees) {
      newVariables['assigneeLogins'] = assignees
      newVariables['withAssignees'] = true
    }

    const labels = routeParams.searchParams.get('labels')
    if (labels) {
      newVariables['labelNames'] = labels
      newVariables['withLabels'] = true
    }

    const milestone = routeParams.searchParams.get('milestone')
    if (milestone) {
      newVariables['milestoneTitle'] = milestone
      newVariables['withMilestone'] = true
    }

    const projects = routeParams.searchParams.get('projects')
    if (routeParams && projects) {
      const projectNumbers = parseValidProjectNumbersFromUrlParameter(projects, routeParams.pathParams['owner'])

      if (projectNumbers.length > 0) {
        newVariables['projectNumbers'] = projectNumbers
        newVariables['withProjects'] = true
      }
    }

    const type = routeParams.searchParams.get('type')
    if (type) {
      newVariables['type'] = type
      newVariables['withType'] = true
    }

    const discussionParam = routeParams.searchParams.get('created_from_discussion_number')
    if (discussionParam) {
      const discussionNumber = parseInt(discussionParam, 10)
      newVariables['discussionNumber'] = isValidInteger(discussionParam) ? discussionNumber : 0
      newVariables['includeDiscussion'] = isValidInteger(discussionParam) && !!discussionNumber
    }

    const template = routeParams.searchParams.get('template')
    if (template) {
      newVariables['templateFilter'] = template
      newVariables['withTemplate'] = true
    }

    newVariables['withTriagePermission'] = newVariables['withType'] || newVariables['withProjects'] || false

    return newVariables
  },
  '/:owner/:name/issues/new/choose': variables => {
    return variables
  },
  '/:owner/:repo/issues/created_by/app/:author': (variables, routeParams) => {
    const newRouteParams = {...routeParams}
    newRouteParams.pathParams = {
      ...routeParams.pathParams,
      author: `app/${routeParams.pathParams['author']}`,
    }
    const newVariables = variablesIndex(variables, newRouteParams)
    return newVariables
  },
  '/:owner/:repo/milestone/:number': (variables, routeParams) => {
    const newVariables = variables
    newVariables['id'] = REPOSITORY_VIEW.id
    newVariables['first'] = VALUES.issuesPageSize
    newVariables['owner'] = routeParams.pathParams['owner']!
    newVariables['name'] = routeParams.pathParams['repo']!
    const milestoneNumberParam = routeParams.pathParams['number']!

    const showClosed = routeParams.searchParams.get('closed') === '1'

    const issueState = showClosed ? 'closed' : 'open'

    newVariables['skip'] = 0
    const pageParam = routeParams.searchParams.get('page')
    if (pageParam && isValidInteger(pageParam) && parseInt(pageParam, 10) > 1) {
      newVariables['skip'] = (parseInt(pageParam, 10) - 1) * VALUES.issuesPageSize
    }

    if (milestoneNumberParam) {
      const milestoneNumber = parseInt(milestoneNumberParam, 10)
      newVariables['number'] = isValidInteger(milestoneNumberParam) ? milestoneNumber : 0
      newVariables['query'] =
        `state:${issueState} milestone-number:${newVariables['number']} archived:false sort:milestone_prio-desc`
    }

    return newVariables
  },
  '/:owner/:repo/milestones': (variables, routeParams) => {
    const newVariables = variables
    newVariables['owner'] = routeParams.pathParams['owner']!
    newVariables['name'] = routeParams.pathParams['repo']!
    const showClosed = routeParams.searchParams.get('state') === 'closed'
    newVariables['state'] = showClosed ? 'CLOSED' : 'OPEN'
    const sort = routeParams.searchParams.get('sort')
    const direction = routeParams.searchParams.get('direction')
    if (sort && direction) {
      if (sort === 'due_date') {
        newVariables['orderField'] = 'DUE_DATE'
      }
      if (sort === 'completeness') {
        newVariables['orderField'] = 'COMPLETED'
      }
      if (sort === 'title') {
        newVariables['orderField'] = 'ALPHABETICAL'
      }
      if (sort === 'count') {
        newVariables['orderField'] = 'ISSUES'
      }
      if (direction === 'asc') {
        newVariables['orderDirection'] = 'ASC'
      } else {
        newVariables['orderDirection'] = 'DESC'
      }
    }

    return newVariables
  },
  '/:owner/:repo/milestones/new': (variables, routeParams) => {
    const newVariables = variables
    newVariables['owner'] = routeParams.pathParams['owner']!
    newVariables['name'] = routeParams.pathParams['repo']!
    return newVariables
  },
  '/:owner/:repo/milestones/:number/edit': (variables, routeParams) => {
    const newVariables = variables

    const milestoneNumberParam = routeParams.pathParams['number']!

    newVariables['owner'] = routeParams.pathParams['owner']
    newVariables['name'] = routeParams.pathParams['repo']

    if (milestoneNumberParam) {
      const milestoneNumber = parseInt(milestoneNumberParam, 10)
      newVariables['number'] = isValidInteger(milestoneNumberParam) ? milestoneNumber : 0
    }

    return newVariables
  },
  '/:owner/:repo/labels': (variables, routeParams) => {
    const newVariables = variables
    newVariables['owner'] = routeParams.pathParams['owner']!
    newVariables['name'] = routeParams.pathParams['repo']!
    newVariables['first'] = CONSTS.labelsPageSize

    newVariables['skip'] = 0
    const pageParam = routeParams.searchParams.get('page')
    if (pageParam && isValidInteger(pageParam) && parseInt(pageParam, 10) > 1) {
      newVariables['skip'] = (parseInt(pageParam, 10) - 1) * CONSTS.labelsPageSize
    }
    const sort = routeParams.searchParams.get('sort')
    if (sort) {
      const [option, direction] = sort.split('-')
      if (option === 'name') {
        newVariables['orderField'] = 'NAME'
        newVariables['orderDirection'] = direction === 'asc' ? 'ASC' : 'DESC'
      } else if (option === 'count') {
        newVariables['orderField'] = 'ISSUE_COUNT'
        newVariables['orderDirection'] = direction === 'asc' ? 'ASC' : 'DESC'
      }
    }

    const urlQuery = routeParams.searchParams.get('q')
    if (urlQuery) {
      newVariables['query'] = replaceDateTokens(urlQuery)
    }

    return newVariables
  },
  '/:owner/:repo/issues': variablesIndex,
  '/:owner/:repo/issues/created_by/:author': variablesIndex,
  '/:owner/:repo/issues/assigned/:assignee': variablesIndex,
  '/:owner/:repo/issues/mentioned/:mentioned': variablesIndex,
  '/:owner/:repo/labels/:label': variablesIndex,
  '/issues/:id': (variables, routeParams, environment) => {
    const newVariables = variables
    let viewId
    if (routeParams) {
      viewId = routeParams.pathParams['id']
    }
    if (viewId && environment) {
      const urlQuery = routeParams.searchParams.get('q')
      const viewNode = environment.getStore().getSource().get(viewId)
      if (viewNode) {
        if (urlQuery) {
          newVariables['query'] = replaceDateTokens(urlQuery)
          newVariables['includeReactions'] = findSortReactionInQuery(urlQuery)
        } else if (viewNode.query) {
          newVariables['query'] = replaceDateTokens(`${viewNode.query}`)
          newVariables['includeReactions'] = findSortReactionInQuery(`${viewNode.query}`)
        }
      }
    }
    addPagingParams(routeParams.searchParams, newVariables)
    return newVariables
  },
  '/:owner/:repo/issues/:number': variables => {
    const newVariables = variables

    newVariables['id'] = REPOSITORY_VIEW.id

    return newVariables
  },
  '/issues': (variables, routeParams) => {
    const newVariables = variables
    const urlQuery = routeParams.searchParams.get('q')
    if (urlQuery) {
      newVariables['query'] = replaceDateTokens(urlQuery)
      newVariables['includeReactions'] = findSortReactionInQuery(urlQuery)
    }
    addPagingParams(routeParams.searchParams, newVariables)

    return newVariables
  },
  '/issues/assigned': (variables, routeParams) => {
    const newVariables = variables
    const urlQuery = routeParams.searchParams.get('q')

    newVariables['query'] = urlQuery ? replaceDateTokens(urlQuery) : QUERIES.assignedToMe
    addPagingParams(routeParams.searchParams, newVariables)

    return newVariables
  },
  '/issues/mentioned': (variables, routeParams) => {
    const newVariables = variables
    const urlQuery = routeParams.searchParams.get('q')

    newVariables['query'] = urlQuery ? replaceDateTokens(urlQuery) : QUERIES.mentioned
    addPagingParams(routeParams.searchParams, newVariables)

    return newVariables
  },
  '/issues/recent': (variables, routeParams) => {
    const newVariables = variables
    const urlQuery = routeParams.searchParams.get('q')

    newVariables['query'] = replaceDateTokens(urlQuery ? urlQuery : QUERIES.recentActivity)
    addPagingParams(routeParams.searchParams, newVariables)

    return newVariables
  },
  '/issues/created': (variables, routeParams) => {
    const newVariables = variables
    const urlQuery = routeParams.searchParams.get('q')

    newVariables['query'] = urlQuery ? replaceDateTokens(urlQuery) : QUERIES.createdByMe
    addPagingParams(routeParams.searchParams, newVariables)

    return newVariables
  },
})

export const isValidInteger = (value: string) => {
  //regex to validate if input string is an integer
  return /^\s*-?\d+\s*$/.test(value)
}
