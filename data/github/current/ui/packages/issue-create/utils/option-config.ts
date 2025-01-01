import {VALUES} from '../constants/values'
import {DisplayMode} from './display-mode'
import type {IssueCreateArguments} from './template-args'

type ScopedAssignee = {
  avatarUrl: string
  login: string
}

export type UserSettingsOptionConfig = {
  pasteUrlsAsPlainText?: boolean
  useMonospaceFont?: boolean
  singleKeyShortcutsEnabled?: boolean
  emojiSkinTonePreference?: number
  copilotShowFunctionality?: boolean
}

// Separate out the options that are required to have default non-undefined values
type RequiredOptionConfig = {
  showFullScreenButton?: boolean
  navigateToFullScreenOnTemplateChoice?: boolean
  insidePortal?: boolean
  storageKeyPrefix?: string
} & UserSettingsOptionConfig

type UndefinableOptionConfig = {
  showRepositoryPicker?: boolean
  scopedOrganization?: string
  scopedProjectTitle?: string
  scopedIssueType?: string
  scopedMilestone?: string
  scopedAssignees?: ScopedAssignee[]
  issueCreateArguments?: IssueCreateArguments
  defaultDisplayMode?: DisplayMode
  returnFocusRef?: React.RefObject<HTMLElement>
  emojiSkinTonePreference?: number
  canBypassTemplateSelection?: boolean
  navigate?: (url: string) => void
}

// Additional helper properties
type OptionConfigProperties = {
  getDefaultDisplayMode: (fallback: DisplayMode | undefined) => DisplayMode
}

export type IssueCreateOptionConfig = RequiredOptionConfig & UndefinableOptionConfig

export type SafeOptionConfig = Readonly<
  Required<RequiredOptionConfig> & UndefinableOptionConfig & OptionConfigProperties
>

const OPTION_DEFAULT_CONFIG: Omit<SafeOptionConfig, keyof OptionConfigProperties> = {
  pasteUrlsAsPlainText: false,
  useMonospaceFont: false,
  singleKeyShortcutsEnabled: false,
  showFullScreenButton: false,
  navigateToFullScreenOnTemplateChoice: false,
  insidePortal: true, // Assume true given most cases are inside the dialog
  showRepositoryPicker: true,
  storageKeyPrefix: '',
  canBypassTemplateSelection: false,
  emojiSkinTonePreference: 0,
  copilotShowFunctionality: false,
}

// This method is used to ensure we only default on values that weren't explicitly specified.
export const getSafeConfig = (config: IssueCreateOptionConfig | undefined): SafeOptionConfig => {
  const filledConfig = {
    ...OPTION_DEFAULT_CONFIG,
    ...config,
  }

  // These are values we want to override before returning, as they take precedence over the default values
  // and depend on the values of other config properties.
  const repoNwo = filledConfig.issueCreateArguments?.repository
    ? `${filledConfig.issueCreateArguments?.repository.owner}-${filledConfig.issueCreateArguments?.repository.name}`
    : undefined
  const overrides = {
    storageKeyPrefix: repoNwo ?? filledConfig.storageKeyPrefix ?? VALUES.storageKeyPrefixes.defaultFallback,
  }

  const configProperties: OptionConfigProperties = {
    getDefaultDisplayMode: (fallback: DisplayMode | undefined) =>
      filledConfig.defaultDisplayMode ?? fallback ?? DisplayMode.TemplatePicker,
  }

  return {
    ...filledConfig,
    ...overrides,
    ...configProperties,
  }
}

export const getDefaultConfig = (): SafeOptionConfig => getSafeConfig(undefined)
