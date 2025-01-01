import {isFeatureEnabled} from '@github-ui/feature-flags'

import {
  CLIENT_SKILL_REGISTRY,
  type ClientSkillEntry,
  type ClientSkillWithExclusion,
  type ClientSkillWithInclusion,
} from './client-skills-registry'
import type {ClientSideSkillDefinition} from './copilot-chat-types'

export const registerSkillsForPath = (path: string) => {
  return Object.keys(CLIENT_SKILL_REGISTRY).reduce((acc: ClientSideSkillDefinition[], skillName: string) => {
    const skill = CLIENT_SKILL_REGISTRY[skillName]
    if (!skill) return acc
    if (skill.featureFlag && !isFeatureEnabled(skill.featureFlag)) return acc
    if (isClientSkillWithExclusion(skill)) {
      // Do not register the skill if the current URL is in the skill's excludePaths
      if (skill.excludePaths.some(excludePath => excludePath.test(path))) return acc
    } else if (isClientSkillWithInclusion(skill)) {
      // Do not register the skill if the current URL does not match one of the skill's includePaths
      if (!skill.includePaths.some(includePath => includePath.test(path))) return acc
    } else {
      // Do not register the skill if it does not specify where it should be included or excluded
      return acc
    }
    acc.push(skill.schema)
    return acc
  }, [])
}
const isClientSkillWithInclusion = (entry: ClientSkillEntry): entry is ClientSkillWithInclusion => {
  return 'includePaths' in entry
}

const isClientSkillWithExclusion = (entry: ClientSkillEntry): entry is ClientSkillWithExclusion => {
  return 'excludePaths' in entry
}
