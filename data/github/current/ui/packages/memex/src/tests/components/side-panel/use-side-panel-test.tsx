import {noop} from '@github-ui/noop'
import {act, render, renderHook, screen, waitFor} from '@testing-library/react'
import {userEvent} from '@testing-library/user-event'
import {useEffect} from 'react'
import invariant from 'tiny-invariant'

import {ItemType} from '../../../client/api/memex-items/item-type'
import {SidePanelTypeParam} from '../../../client/api/memex-items/side-panel-item'
import {apiPostStats} from '../../../client/api/stats/api-post-stats'
import {type MemexItemSidePanelState, useSidePanel} from '../../../client/hooks/use-side-panel'
import {createMemexItemModel} from '../../../client/models/memex-item-model'
import {ITEM_ID_PARAM, PANE_PARAM} from '../../../client/platform/url'
import {useSearchParams} from '../../../client/router'
import {DefaultClosedIssue, DefaultOpenIssue} from '../../../mocks/memex-items'
import {stubResolvedApiResponse} from '../../mocks/api/memex'
import {stubGetItem} from '../../mocks/api/memex-items'
import {setupEnvironment} from './side-panel-test-helpers'

jest.mock('../../../client/api/stats/api-post-stats')

// Mock use-paginated-memex-items-query dependencies
jest.mock('../../../client/hooks/use-views', () => {
  const originalModule = jest.requireActual('../../../client/hooks/use-views')
  return {
    __esModule: true,
    ...originalModule,
    useViews: () => ({currentView: undefined}),
  }
})
jest.mock('../../../client/hooks/use-sorted-by', () => ({
  useSortedBy: () => ({sorts: []}),
}))
jest.mock('../../../client/features/grouping/hooks/use-horizontal-grouped-by', () => ({
  useHorizontalGroupedBy: () => ({groupedByColumnId: undefined}),
}))
jest.mock('../../../client/features/grouping/hooks/use-vertical-grouped-by', () => ({
  useVerticalGroupedBy: () => ({groupedByColumnId: undefined}),
}))
jest.mock('../../../client/features/slicing/hooks/use-slice-by', () => ({
  useSliceBy: () => ({sliceField: undefined}),
}))

describe('useSidePanel', () => {
  it('has no active item by default', () => {
    const {result} = renderHook(useSidePanel, {wrapper: setupEnvironment().wrapper})

    expect(result.current.sidePanelState).toBeNull()
  })

  describe('focus', () => {
    const TestComponent = () => {
      const {initialFocusRef, openProjectItemInPane} = useSidePanel()

      useEffect(() => {
        openProjectItemInPane(createMemexItemModel(DefaultOpenIssue))
        // eslint-disable-next-line react-hooks/exhaustive-deps
      }, [])

      const openNewItem = () => {
        openProjectItemInPane(createMemexItemModel(DefaultClosedIssue))
      }

      return (
        <>
          <button ref={initialFocusRef}>I want focus</button>
          <button onClick={openNewItem}>Open new item</button>
        </>
      )
    }

    it('focuses the chosen element on render', async () => {
      render(<TestComponent />, {wrapper: setupEnvironment().wrapper})

      const focusButton = screen.getByText('I want focus')
      expect(focusButton).not.toHaveFocus()

      await waitFor(() => expect(focusButton).toHaveFocus())
    })

    it('focuses the chosen element when changing items', async () => {
      render(<TestComponent />, {wrapper: setupEnvironment().wrapper})

      const focusButton = screen.getByText('I want focus')
      await waitFor(() => expect(focusButton).toHaveFocus())

      await userEvent.tab()

      expect(focusButton).not.toHaveFocus()

      await userEvent.click(screen.getByText('Open new item'))

      await waitFor(() => expect(focusButton).toHaveFocus())
    })
  })

  it('is closed by default', () => {
    const {result} = renderHook(useSidePanel, {wrapper: setupEnvironment().wrapper})

    expect(result.current.isPaneOpened).toBe(false)
  })

  it('has active draft item when pane is opened', async () => {
    const environment = setupEnvironment()
    const {result} = renderHook(useSidePanel, {wrapper: environment.wrapper})
    const item = environment.itemModels.find(model => model.contentType === ItemType.DraftIssue)!

    act(() => {
      result.current.openProjectItemInPane(item, noop)
    })
    expect(result.current.isPaneOpened).toEqual(true)
    await waitFor(() => expect((result.current.sidePanelState as MemexItemSidePanelState).item?.id).toEqual(item.id))
  })

  it('has active issue item when pane is opened', async () => {
    const environment = setupEnvironment()
    const {result} = renderHook(useSidePanel, {wrapper: environment.wrapper})
    const item = environment.itemModels.find(model => model.contentType === ItemType.Issue)!

    act(() => {
      result.current.openProjectItemInPane(item, noop)
    })
    expect(result.current.isPaneOpened).toEqual(true)
    await waitFor(() => expect((result.current.sidePanelState as MemexItemSidePanelState).item?.id).toEqual(item.id))
  })

  it('is opened after calling openPaneInfo', () => {
    const {result} = renderHook(useSidePanel, {wrapper: setupEnvironment().wrapper})

    act(() => {
      result.current.openPaneInfo()
    })

    expect(result.current.isPaneOpened).toEqual(true)
  })

  it('clears active item when pane is closed', async () => {
    stubResolvedApiResponse(apiPostStats, {success: true})

    const {wrapper, itemModels} = setupEnvironment()
    const {result} = renderHook(useSidePanel, {wrapper})

    const item = itemModels.find(i => i.contentType === 'DraftIssue')
    invariant(item != null)
    const onClose = jest.fn()

    act(() => {
      result.current.openProjectItemInPane(item, () => onClose())
    })
    await act(() => result.current.closePane())

    expect(result.current.sidePanelState).toBeNull()
    await waitFor(() => expect(onClose).toHaveBeenCalledTimes(1))
  })

  it('is closed after calling close', async () => {
    const {wrapper, itemModels} = setupEnvironment()
    const {result} = renderHook(useSidePanel, {wrapper})

    const item = itemModels.find(i => i.contentType === 'DraftIssue')
    invariant(item != null)
    const onClose = jest.fn()

    act(() => {
      result.current.openProjectItemInPane(item, () => onClose())
    })
    await act(() => result.current.closePane())

    expect(result.current.isPaneOpened).toEqual(false)
    await waitFor(() => expect(onClose).toHaveBeenCalledTimes(1))
  })

  it('fetches draft item from server using openProjectItemPane', async () => {
    const environment = setupEnvironment()
    const {result} = renderHook(useSidePanel, {wrapper: environment.wrapper})
    const item = environment.itemModels.find(model => model.contentType === ItemType.DraftIssue)!
    const getItemStub = stubGetItem(item)

    act(() => {
      result.current.openProjectItemInPane(item, noop)
    })
    expect(result.current.isPaneOpened).toEqual(true)
    await waitFor(() => expect((result.current.sidePanelState as MemexItemSidePanelState).item?.id).toEqual(item.id))
    expect(getItemStub).toHaveBeenCalledTimes(1)
  })

  it('fetches draft item from server using search params', async () => {
    const environment = setupEnvironment()
    const {result} = renderHook(
      () => ({
        useSidePanel: useSidePanel(),
        useSearchParams: useSearchParams(),
      }),
      {wrapper: environment.wrapper},
    )
    const item = environment.itemModels.find(model => model.contentType === ItemType.DraftIssue)!
    const getItemStub = stubGetItem(item)

    act(() => {
      const [_, setSearchParams] = result.current.useSearchParams
      setSearchParams(nextParams => {
        nextParams.set(PANE_PARAM, SidePanelTypeParam.ISSUE)
        nextParams.set(ITEM_ID_PARAM, item.id.toString())
        return nextParams
      })
    })
    await waitFor(() =>
      expect((result.current.useSidePanel.sidePanelState as MemexItemSidePanelState).item?.id).toEqual(item.id),
    )
    expect(result.current.useSidePanel.isPaneOpened).toEqual(true)
    expect(getItemStub).toHaveBeenCalledTimes(1)
  })
})
