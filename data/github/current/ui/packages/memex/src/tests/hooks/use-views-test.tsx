import {renderHook} from '@testing-library/react'

import {useViews} from '../../client/hooks/use-views'
import {buildSystemColumns} from '../factories/columns/system-column-factory'
import {viewFactory} from '../factories/views/view-factory'
import {createTestEnvironment, TestAppContainer} from '../test-app-wrapper'

const renderUseViewsHook = (enablePWL: boolean) => {
  createTestEnvironment({
    'memex-enabled-features': enablePWL ? ['memex_table_without_limits'] : [],
    'memex-columns-data': buildSystemColumns(),
    'memex-views': [
      viewFactory.table().build({
        filter: 'status:todo', // an unloaded column id
      }),
    ],
  })
  return renderHook(() => useViews(), {wrapper: TestAppContainer})
}

describe('useViews.missingRequiredColumnData', () => {
  it('is true when the filter references an unloaded column', () => {
    const {result} = renderUseViewsHook(false)
    expect(result.current.missingRequiredColumnData).toBe(true)
  })
  it('is false when memex_table_without_limits is true, even if filter references an unloaded column', () => {
    const {result} = renderUseViewsHook(true)
    expect(result.current.missingRequiredColumnData).toBe(false)
  })
})
