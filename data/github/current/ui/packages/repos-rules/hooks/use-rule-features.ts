import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {RuleFeatures} from '../types/rules-types'

export type AppPayloadWithFeatures = {supported_features?: RuleFeatures}

export const useRuleFeatures = () =>
  useAppPayload<AppPayloadWithFeatures>()?.supported_features ?? {
    historyEnabled: false,
    importExportEnabled: false,
    supportedTargets: ['branch', 'tag'],
    listViewEnabled: true,
  }
