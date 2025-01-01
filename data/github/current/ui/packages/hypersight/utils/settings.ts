import type {Classification, Template} from './types'

export type BaseUserSettings = {
  technicalKnowledge: number
  instructions: string
  language: string
  writingStyle: 'Normal' | 'Concise' | 'Explanatory' | 'Formal'
  classifications: Classification[]
  templates: Template[]
}

export const DEFAULT_TEMPLATE: Template = {
  name: 'Default',
  instructions:
    'Walk through the changes in a clear and organized manner, highlighting the most important modifications first.',
}
export const DEFAULT_SETTINGS: BaseUserSettings = {
  technicalKnowledge: 5,
  instructions: `Highlight key changes in the diff.  Tests, documentation, dependencies, and other changes should have a low priority.`,
  language: 'English',
  writingStyle: 'Normal',
  templates: [DEFAULT_TEMPLATE],
  classifications: [
    {
      name: 'Bug fix',
      description: 'A change that addresses incorrect or unexpected behavior in the existing code.',
    },
    {
      name: 'Feature',
      description: 'Introduction of a new feature or a notable enhancement to existing functionality.',
    },
    {
      name: 'Refactor',
      description:
        'Reorganization of code for improved clarity, maintainability, or structure without changing external behavior.',
    },
    {
      name: 'Performance',
      description: 'Changes that optimize the speed, efficiency, or scalability of the application.',
    },
    {
      name: 'Security',
      description: "A change that addresses a security vulnerability or hardens the system's security posture.",
    },
    {
      name: 'Documentation',
      description: 'Any PR that updates or adds documentation (README, user manuals, code comments, etc.).',
    },
    {
      name: 'Testing',
      description:
        'Additions or revisions to tests (unit, integration, end-to-end) aimed at improving coverage or reliability.',
    },
    {
      name: 'Build/CI',
      description:
        'Modifications to library/package dependencies, build scripts, or continuous integration configuration.',
    },
    {
      name: 'Chore',
      description:
        "General housekeeping that doesn't fall under the above categories (e.g., version bumps, minor configurations, or grooming tasks).",
    },
    {
      name: 'UX',
      description: 'Changes specifically aimed at user interface or user experience improvements.',
    },
    {
      name: 'Other',
      description: "Changes that don't fit into any other category.",
    },
  ],
}
export const technicalKnowledgeDescriptions = [
  'The user is non-technical with minimal technical knowledge. Provide simple, jargon-free explanations and assume no prior familiarity with programming or technical concepts.',
  'The user has some technical familiarity or is a novice developer. Use basic terminology and offer gentle introductions to new concepts, clarifying any technical terms as needed.',
  'The user is an intermediate / mid-level engineer. Give moderately detailed explanations, assuming fundamental programming knowledge but expanding on complex topics when necessary.',
  'The user is an advanced / senior engineer. Provide in-depth, technical insights with references to best practices, patterns, and trade-offs in architectural decisions.',
  'The user is a principal or staff-level engineer. Discuss topics at a highly advanced level, referencing sophisticated design principles and cutting-edge engineering practices.',
]
