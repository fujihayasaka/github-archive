export type Rule = {paths: string; link: string; name: string}

export type ContentExclusionSettingsProps = {
  locationCopy: string
  applyCopy: string
  entLevelRules?: Rule[] | null
  orgLevelRules?: Rule[] | null
  children?: React.ReactNode
}

export type ContentExclusionSettingsPayload = {
  organization?: string
  repo?: string
  lastEdited?: LastEditedPayload
  endpoint?: string
  document?: string
  message?: string
  entLevelRules?: Rule[]
  orgLevelRules?: Rule[]
}

export type LastEditedPayload = {login: string; time: string; link?: string}
