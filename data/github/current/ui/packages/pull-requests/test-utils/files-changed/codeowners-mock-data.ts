import {useCodeowners, usePathOwnership} from '../../page-data/loaders/use-codeowners-data'
import type {UseQueryResult} from '@github-ui/react-query'
import type {Codeowners} from '../../page-data/payloads/codeowners'

export function mockUseCodeownersData<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useCodeowners as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: [],
    ...result,
  })
}

export function mockCodeownersData({makeViewerCodeowner = false}: {makeViewerCodeowner?: boolean}): Codeowners {
  return {
    isEnabled: true,
    isViewerOneOfMultipleCodeowners: makeViewerCodeowner,
    ownershipByPath: {
      'path/to/file': {
        isOwnedByViewer: makeViewerCodeowner,
        owners: ['@monalisa'],
        ruleLineNumber: 1,
        ruleUrl: 'https://example.com/rule',
      },
      'path/to/another/file': {
        isOwnedByViewer: false,
        owners: ['@octocat'],
        ruleLineNumber: 2,
        ruleUrl: 'https://example.com/rule',
      },
    },
  }
}

export function mockUsePathOwnership() {
  ;(usePathOwnership as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: {
      isOwnedByViewer: false,
      owners: [],
      ruleLineNumber: undefined,
      ruleUrl: undefined,
    },
  })
}
