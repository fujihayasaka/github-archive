import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {PageStrings} from '../types/rules-types'

export type AppPayloadWithStrings = {page_strings?: PageStrings}

export const useRuleStrings = () =>
  useAppPayload<AppPayloadWithStrings>()?.page_strings ?? {
    heading: 'Rulesets',
    alphaOrBeta: '',
    headingText: "You haven't created any rulesets",
    rulesetOrPolicy: 'ruleset',
    rulesetsOrPolicies: 'rulesets',
    ruleOrPolicy: 'rule',
    rulesOrPolicies: 'rules',
  }
