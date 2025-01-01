import {useMemo} from 'react'
import type {Branch} from '../types'

type BRANCH_PROTECTION_STATE = 'protectedByBranchProtections' | 'protectedByRulesets' | 'unprotected'

type useIsBranchProtectedProps = Pick<Branch, 'rulesetsPath' | 'protectedByBranchProtections'>

export default function useIsBranchProtected({rulesetsPath, protectedByBranchProtections}: useIsBranchProtectedProps) {
  return useMemo(() => {
    let state: BRANCH_PROTECTION_STATE = 'unprotected'
    if (rulesetsPath) {
      state = 'protectedByRulesets'
    } else if (protectedByBranchProtections) {
      state = 'protectedByBranchProtections'
    }
    return {
      isProtectedBy: {
        branchProtections: state === 'protectedByBranchProtections',
        rulesets: state === 'protectedByRulesets',
      },
      isProtected: state !== 'unprotected',
    }
  }, [protectedByBranchProtections, rulesetsPath])
}
