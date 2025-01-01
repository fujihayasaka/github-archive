import {
  orgRulesetsTargetCountPath,
  stafftoolsOrgRulesetsTargetCountPath,
  repoRulesetsTargetCountPath,
  stafftoolsRepoRulesetsTargetCountPath,
} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useState, useEffect} from 'react'
import type {Ruleset, SourceType} from '../types/rules-types'
import type {Repository} from '@github-ui/current-repository'
import type {Organization} from '@github-ui/repos-types'
import {useIsStafftools} from './use-is-stafftools'

type RulesetPreviewCount = Record<string, number>
type RulesetPreviewSamples = Record<string, string[]>
type RulesetPreviewErrors = Record<string, string>
type RulesetPreviewUrls = Record<string, string>

interface RulesetsTargetPreviewDataRow {
  rulesetId: number
  count: number
  sampleTargetNames?: string[]
  errorMessage?: string
  url?: string
}

interface RulesetsTargetPreviewData {
  preview: RulesetsTargetPreviewDataRow[]
}

const BATCHSIZE = 10

function dataProcessor<T extends keyof RulesetsTargetPreviewDataRow>(
  data: RulesetsTargetPreviewData,
  propertyName: T,
): Record<string, Required<RulesetsTargetPreviewDataRow>[T]> {
  if (!data?.preview) return {}

  const entries = data.preview.map(item => [item.rulesetId, item[propertyName]])

  return Object.fromEntries(entries)
}

export function useTargetCount(
  source: Repository | Organization,
  sourceType: SourceType,
  rulesets: Ruleset[],
  batchSize = BATCHSIZE,
): {
  rulesetPreviewCounts: RulesetPreviewCount
  rulesetPreviewSamples: RulesetPreviewSamples
  rulesetPreviewErrors: RulesetPreviewErrors
  rulesetPreviewUrls: RulesetPreviewUrls
} {
  const isStafftools = useIsStafftools()

  const [rulesetPreviewCounts, setRulesetPreviewCount] = useState({})
  const [rulesetPreviewSamples, setRulesetPreviewSamples] = useState({})
  const [rulesetPreviewErrors, setRulesetPreviewErrors] = useState({})
  const [rulesetPreviewUrls, setRulesetPreviewUrls] = useState<Record<string, string>>({})

  useEffect(() => {
    async function fetchAllInBatches(
      items: Ruleset[],
      url: string,
      {itemsPerGroup = batchSize}: {itemsPerGroup?: number} = {},
    ) {
      for (let i = 0; i < items.length; i += itemsPerGroup) {
        const batchIds = items.slice(i, i + itemsPerGroup).map(r => r.id)
        try {
          if (cancelled) {
            return
          }
          const result = await verifiedFetchJSON(url, {body: {ruleset_ids: batchIds}, method: 'POST'})
          const data = (await result.json()) as RulesetsTargetPreviewData
          setRulesetPreviewCount(prev => ({...prev, ...dataProcessor(data, 'count')}))
          setRulesetPreviewSamples(prev => ({
            ...prev,
            ...dataProcessor(data, 'sampleTargetNames'),
          }))
          setRulesetPreviewErrors(prev => ({
            ...prev,
            ...dataProcessor(data, 'errorMessage'),
          }))
          setRulesetPreviewUrls(prev => ({
            ...prev,
            ...dataProcessor(data, 'url'),
          }))
        } catch {
          return {}
        }
      }
    }

    async function fetchAllSingleBatch(items: Ruleset[], url: string) {
      fetchAllInBatches(items, url, {itemsPerGroup: items.length})
    }

    let cancelled = false

    async function fetchOrgLevelPreviews(organization: Organization) {
      const url = isStafftools
        ? stafftoolsOrgRulesetsTargetCountPath({owner: organization.name})
        : orgRulesetsTargetCountPath({owner: organization.name})

      const [propertyRulesets, nonPropertyRulesets] = partition(rulesets, ruleset =>
        ruleset.conditions.some(condition => condition.target === 'repository_property'),
      )

      if (nonPropertyRulesets.length > 0) {
        await fetchAllSingleBatch(nonPropertyRulesets, url)
      }

      if (propertyRulesets.length > 0) {
        await fetchAllInBatches(propertyRulesets, url)
      }
    }

    async function fetchRepoLevelPreviews(repository: Repository) {
      const url = isStafftools
        ? stafftoolsRepoRulesetsTargetCountPath({owner: repository.ownerLogin, repo: repository.name})
        : repoRulesetsTargetCountPath({owner: repository.ownerLogin, repo: repository.name})
      await fetchAllSingleBatch(rulesets, url)
    }

    switch (sourceType) {
      case 'organization':
        fetchOrgLevelPreviews(source as Organization)
        break
      case 'repository':
        fetchRepoLevelPreviews(source as Repository)
        break
    }

    return function cancel() {
      cancelled = true
    }
  }, [sourceType, source, batchSize, rulesets, isStafftools])

  return {rulesetPreviewCounts, rulesetPreviewSamples, rulesetPreviewErrors, rulesetPreviewUrls}
}

type Predicate<T> = (item: T) => boolean

function partition<T>(items: T[], condition: Predicate<T>): [T[], T[]] {
  const positive: T[] = []
  const negative: T[] = []

  for (const item of items) {
    if (condition(item)) {
      positive.push(item)
    } else {
      negative.push(item)
    }
  }

  return [positive, negative]
}
