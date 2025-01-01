type PageViewSummary = {
  lastVisitedAt: number
  visitCount: number
}

export type PageViews = {[page_key: string]: PageViewSummary}

const TEAM_PAGE_REGEX = /^\/orgs\/([a-z0-9-]+)\/teams\/([\w-]+)/

// Of course this list is incomplete, but it should be good enough for the purposes of this prototype.
const REPOSITORY_PAGE_REGEXES = [
  // This will overcount some things, but since every page view is ultimately compared to entities
  // we can jump to it should be fine. Of course if we ever tried to add users or orgs to this it
  // would break.
  /^\/([^/]+)\/([^/]+)\/?$/,

  /^\/([^/]+)\/([^/]+)\/blob/,
  /^\/([^/]+)\/([^/]+)\/tree/,
  /^\/([^/]+)\/([^/]+)\/issues/,
  /^\/([^/]+)\/([^/]+)\/pulls?/,
  /^\/([^/]+)\/([^/]+)\/pulse/,
]

const PROJECT_PAGE_REGEXES = [
  ['organization', /^\/orgs\/([a-z0-9-]+)\/projects\/([0-9-]+)/],
  ['repository', /^\/([^/]+)\/([^/]+)\/projects\/([0-9-]+)/],
] as const

const MAX_PAGE_VIEWS_TO_STORE_IN_LOCAL_STORAGE = 100

export function logPageView(path: string) {
  const teamPageMatch = path.match(TEAM_PAGE_REGEX)
  const [_teamMatch, organizationLogin, teamSlug] = teamPageMatch || []
  if (typeof organizationLogin === 'string' && typeof teamSlug === 'string') {
    logPageViewByKey(buildTeamKey(organizationLogin, teamSlug))
    return
  }

  for (const [ownerType, projectRegex] of PROJECT_PAGE_REGEXES) {
    const projectPageMatch = path.match(projectRegex)
    if (projectPageMatch) {
      const [_projectMatch, ownerSlug, orgNumber, repoNumber] = projectPageMatch
      let owner
      let number

      switch (ownerType) {
        case 'organization':
          owner = ownerSlug
          number = orgNumber
          break
        case 'repository':
          owner = `${ownerSlug}/${orgNumber}`
          number = repoNumber
          break
        default:
        // Should never get here.
      }
      if (owner && number) {
        logPageViewByKey(buildProjectKey(owner, number))
      }
      return
    }
  }

  for (const repositoryPageRegex of REPOSITORY_PAGE_REGEXES) {
    const repositoryPageMatch = path.match(repositoryPageRegex)
    if (repositoryPageMatch) {
      const [_match, ownerLogin, name] = repositoryPageMatch
      if (typeof ownerLogin !== 'string' || typeof name !== 'string') return
      logPageViewByKey(buildRepositoryKey(ownerLogin, name))
      return
    }
  }
}

// Limits localStorage entries to 100 MAX_PAGE_VIEWS_TO_STORE_IN_LOCAL_STORAGE
function limitedPageViews(pageViews: PageViews) {
  const keys = Object.keys(pageViews)
  if (keys.length <= MAX_PAGE_VIEWS_TO_STORE_IN_LOCAL_STORAGE) {
    return pageViews
  }
  const scorePage = scorer(pageViews)
  const ranked = keys.sort((a, b) => scorePage(b) - scorePage(a)).slice(0, MAX_PAGE_VIEWS_TO_STORE_IN_LOCAL_STORAGE / 2)
  return Object.fromEntries(
    ranked.map(key => {
      if (typeof pageViews[key] === 'undefined') {
        throw new Error(`pageViews[${key}] is undefined`)
      }
      return [key, pageViews[key]]
    }),
  )
}

function logPageViewByKey(key: string) {
  const views = getPageViewsMap()
  const now = currentEpochTimeInSeconds()
  const hit = views[key] || {lastVisitedAt: now, visitCount: 0}
  hit.visitCount += 1
  hit.lastVisitedAt = now
  views[key] = hit
  setPageViewsMap(limitedPageViews(views))
}

function currentEpochTimeInSeconds(): number {
  return Math.floor(Date.now() / 1000)
}

export function buildTeamKey(organizationLogin: string, teamSlug: string): string {
  return `team:${organizationLogin}/${teamSlug}`
}

export function buildRepositoryKey(ownerLogin: string, name: string): string {
  return `repository:${ownerLogin}/${name}`
}

export function buildProjectKey(ownerSlug: string, number: string): string {
  return `project:${ownerSlug}/${number}`
}

const PAGE_VIEW_KEY_REGEX = /^(team|repository|project):[^/]+\/[^/]+(\/([^/]+))?$/
const VIEWS_KEY = 'jump_to:page_views'

function setPageViewsMap(views: PageViews) {
  setItem(VIEWS_KEY, JSON.stringify(views))
}

export function getPageViewsMap(): PageViews {
  const rawData = getItem(VIEWS_KEY)
  if (!rawData) return {}

  let json
  try {
    json = JSON.parse(rawData)
  } catch {
    // Clear localStorage since we know it's bad
    setPageViewsMap({})
    return {}
  }

  const pageViewMap: PageViews = {}
  for (const key in json) {
    if (key.match(PAGE_VIEW_KEY_REGEX)) {
      pageViewMap[key] = json[key]
    }
  }
  return pageViewMap
}

function setItem(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value)
  } catch {
    // Storage quota exceeded.
  }
}

function getItem(key: string): string | null {
  try {
    return window.localStorage.getItem(key)
  } catch {
    // Storage unavailable.
    return null
  }
}

const FEATURE_WEIGHTS = {frequency: 0.6, recency: 0.4}

function sortBy<T>(items: T[], map: (item: T) => number): T[] {
  return items.sort((a, b) => map(a) - map(b))
}

type Scorer = (pageKey: string) => number
export function scorer(pageViews: PageViews): Scorer {
  const frequencies = frequencyMap(pageViews)
  const recencies = recencyMap(pageViews)
  return function (pageKey: string): number {
    return score(frequencies.get(pageKey) || 0, recencies.get(pageKey) || 0)
  }
}

function score(frequency: number, recency: number): number {
  return frequency * FEATURE_WEIGHTS.frequency + recency * FEATURE_WEIGHTS.recency
}

// Scores a relative frequency in the interval [0, 1] where higher means more frequent.
function frequencyMap(pageViews: PageViews): Map<string, number> {
  const totalVisits = [...Object.values(pageViews)].reduce((total, view) => total + view.visitCount, 0)
  return new Map(
    Object.keys(pageViews).map(pageKey => {
      if (pageViews[pageKey] === undefined) throw new Error(`pageViews[${pageKey}] is undefined`)
      return [pageKey, pageViews[pageKey].visitCount / totalVisits]
    }),
  )
}

// Scores a relative recency value in the interval [0, 1] where higher means more recent.
function recencyMap(pageViews: PageViews): Map<string, number> {
  const recencyList = sortBy([...Object.keys(pageViews)], key => pageViews[key]?.lastVisitedAt || 0)
  const totalUniqueVisits = recencyList.length
  return new Map(recencyList.map((key, index) => [key, (index + 1) / totalUniqueVisits]))
}
