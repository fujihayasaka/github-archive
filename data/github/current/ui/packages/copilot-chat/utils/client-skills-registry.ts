import type {ClientSideSkillDefinition} from './copilot-chat-types'
import type {ClientSkillConstructor} from './skills/client-skill'
import {InteractDomSkill} from './skills/interact-dom'
import {NavigateInternallySkill} from './skills/navigate-internally'
import {ReadDomSkill} from './skills/read-dom'
import {ReadLocalWorkspaceFileSkill} from './skills/read-local-workspace-file'

/*
 * The client skill registry is a map of skills that the dotcom chat client can execute. If you want your
 * skill to be able to be executed within dotcom chat, you need to register it here.
 *
 * Additionally, you can *optionally* provide paths where you want dotcom chat to automatically register your skill.
 * This is useful if you want the dotcom chat manager to automatically "pull in" your skill's capabilities on
 * certain pages.
 *
 * To register a skill, add an entry to the CLIENT_SKILL_REGISTRY object. Each skill should have a unique name/slug
 * to identify it. Each skill MUST have:
 * - a `schema` property that defines the skill. This is how the model will know when to use your skill.
 * - a `constructor` property that will build an instance of your skill when it needs to be executed
 *
 * Additionally, each skill MAY have:
 * - a `featureFlag`: The feature flag that enables this skill. If this feature flag is not enabled,
 *   the skill will not be registered, as available to the model, or executed if chosen.
 * - an `includePaths`: An array of regexes that will be used to match against the current path.
 *   If the current path matches this regex, the skill WILL be registered as available to be executed.
 * - an `excludePaths` An array of regexes that will be used to match against the current path.
 *   If the current path matches this regex, the skill WILL NOT be registered as available to be executed
 *
 * Please note that a skill can have EITHER an `includePath` or an `excludePath` property, but not both. If a skill
 * has neither an `includePath` nor an `excludePath` property, it will not be automatically registered with chat, but
 * can still be executed if passed into the createMessage endpoint directly (ie via button click or API call, etc).
 *
 */

const PULL_EDIT_PATH_REGEX = /^\/[^/]+\/[^/]+\/pull\/\d+\/edit$/
const SETTINGS_PATH_REGEX = /^\/settings\/.*/
const IMMERSIVE_PATH_REGEX = /^\/copilot(\/.*)?$/

export const CLIENT_SKILL_REGISTRY: SkillRegistry = {
  'read-local-workspace-file': {
    constructor: ReadLocalWorkspaceFileSkill,
    schema: ReadLocalWorkspaceFileSkill.schema(),
    includePaths: [PULL_EDIT_PATH_REGEX],
    featureFlag: 'workspace_editor_fix_a_build_function_calling',
  },
  'read-dom': {
    constructor: ReadDomSkill,
    schema: ReadDomSkill.schema(),
    excludePaths: [SETTINGS_PATH_REGEX],
    featureFlag: 'copilot_client_dom_skills',
  },
  'interact-dom': {
    constructor: InteractDomSkill,
    schema: InteractDomSkill.schema(),
    excludePaths: [SETTINGS_PATH_REGEX],
    featureFlag: 'copilot_client_dom_skills',
  },
  'navigate-internally': {
    constructor: NavigateInternallySkill,
    schema: NavigateInternallySkill.schema(),
    includePaths: [IMMERSIVE_PATH_REGEX],
    featureFlag: 'copilot_workbench',
  },
}

export type SkillRegistry = {
  [key: string]: ClientSkillEntry
}

export type ClientSkillEntry = ClientSkillWithExclusion | ClientSkillWithInclusion | BaseClientSkillEntry
interface BaseClientSkillEntry {
  constructor: ClientSkillConstructor
  featureFlag?: string
  schema: ClientSideSkillDefinition
}

export interface ClientSkillWithInclusion extends BaseClientSkillEntry {
  includePaths: RegExp[]
  excludePaths?: never
}

export interface ClientSkillWithExclusion extends BaseClientSkillEntry {
  includePaths?: never
  excludePaths: RegExp[]
}
