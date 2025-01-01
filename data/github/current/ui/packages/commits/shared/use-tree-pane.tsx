// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {ExpandButton} from '@github-ui/expand-button'
// eslint-disable-next-line no-restricted-imports
import {getCurrentSize, ScreenSize} from '@github-ui/screen-size'
import {useClientValue} from '@github-ui/use-client-value'
import type {ButtonProps, SplitPageLayoutContentProps} from '@primer/react'
import {useCallback, useMemo, useRef, useState} from 'react'

import {type FileTreePreferenceUser, updateFileTreePreference} from '../hooks/use-update-user-tree-preference'

type ExpandTreeFunction = () => void
type CollapseTreeFunction = () => void

interface TreePane {
  splitPagePaneHidden: boolean
  splitPageContentHidden: SplitPageLayoutContentProps['hidden']
  treeToggleElement: JSX.Element
  treeToggleRef: React.RefObject<HTMLButtonElement>
  expandTree: ExpandTreeFunction
  collapseTree: CollapseTreeFunction
  isTreeExpanded: boolean
  isMobileTreeExpanded: boolean
}

interface ToggleButtonOptions {
  size?: ButtonProps['size']
  mobileBreakpoint?: 'sm' | 'md' | 'lg'
}

const BreakpointToScreenSize = {
  sm: ScreenSize.small,
  md: ScreenSize.medium,
  lg: ScreenSize.large,
}

const defaultToggleButtonOptions: ToggleButtonOptions = {
  size: 'medium',
  mobileBreakpoint: 'md',
}

export function useTreePane(
  fileTreeId: string,
  userPrefTreeExpanded: boolean,
  currentUser?: FileTreePreferenceUser,
  toggleButtonOptions?: Partial<ToggleButtonOptions>,
): TreePane {
  const expandButtonOptions = {
    ...defaultToggleButtonOptions,
    ...toggleButtonOptions,
  }

  const [isSSR] = useClientValue(() => false, true, [])

  const treeToggleRef = useRef<HTMLButtonElement>(null)
  const mobileTreeToggleRef = useRef<HTMLButtonElement>(null)
  const mobileBreakpointScreenSize = BreakpointToScreenSize[expandButtonOptions.mobileBreakpoint ?? 'md']

  const [isTreeExpanded, setIsTreeExpanded] = useState(userPrefTreeExpanded)
  const [isMobileTreeExpanded, setIsMobileTreeExpanded] = useState(false)

  const expandTree: ExpandTreeFunction = useCallback(() => {
    // we can do this since we're now on the client when this occurs
    const currentSize = getCurrentSize(window.innerWidth)

    if (currentSize <= mobileBreakpointScreenSize) {
      setIsMobileTreeExpanded(true)
      requestAnimationFrame(() => mobileTreeToggleRef.current?.focus())
    } else {
      setIsTreeExpanded(true)
      updateFileTreePreference(true, currentUser)
      requestAnimationFrame(() => treeToggleRef.current?.focus())
    }
  }, [mobileBreakpointScreenSize, currentUser])

  const collapseTree: CollapseTreeFunction = useCallback(() => {
    // we can do this since we're now on the client when this occurs
    const currentSize = getCurrentSize(window.innerWidth)

    if (currentSize <= mobileBreakpointScreenSize) {
      setIsMobileTreeExpanded(false)
      requestAnimationFrame(() => mobileTreeToggleRef.current?.focus())
    } else {
      setIsTreeExpanded(false)
      updateFileTreePreference(false, currentUser)
      requestAnimationFrame(() => treeToggleRef.current?.focus())
    }
  }, [mobileBreakpointScreenSize, currentUser])

  const regularTreeToggleElement = useMemo(
    () => (
      <ExpandButton
        expanded={isTreeExpanded}
        alignment="left"
        ariaLabel={isTreeExpanded ? 'Collapse file tree' : 'Expand file tree'}
        tooltipDirection="se"
        testid="file-tree-button"
        ariaControls={fileTreeId}
        ref={treeToggleRef}
        onToggleExpanded={() => {
          if (isTreeExpanded) {
            collapseTree()
          } else {
            expandTree()
          }
        }}
        className={`d-none d-${expandButtonOptions.mobileBreakpoint}-flex position-relative`}
        size={expandButtonOptions.size}
      />
    ),
    [
      isTreeExpanded,
      fileTreeId,
      expandButtonOptions.mobileBreakpoint,
      expandButtonOptions.size,
      collapseTree,
      expandTree,
    ],
  )

  const mobileTreeToggleElement = useMemo(
    () => (
      <ExpandButton
        expanded={isMobileTreeExpanded}
        alignment="left"
        ariaLabel={isMobileTreeExpanded ? 'Collapse file tree' : 'Expand file tree'}
        tooltipDirection="se"
        testid="file-tree-button"
        ariaControls={fileTreeId}
        ref={mobileTreeToggleRef}
        onToggleExpanded={() => {
          if (isMobileTreeExpanded) {
            collapseTree()
          } else {
            expandTree()
          }
        }}
        className={`d-${expandButtonOptions.mobileBreakpoint}-none position-relative`}
        size={expandButtonOptions.size}
      />
    ),
    [
      isMobileTreeExpanded,
      fileTreeId,
      expandButtonOptions.mobileBreakpoint,
      expandButtonOptions.size,
      collapseTree,
      expandTree,
    ],
  )

  const treeToggleElement = useMemo(
    () => (
      <>
        {mobileTreeToggleElement}
        {regularTreeToggleElement}
      </>
    ),
    [mobileTreeToggleElement, regularTreeToggleElement],
  )

  return {
    splitPagePaneHidden: isSSR && !userPrefTreeExpanded,
    splitPageContentHidden: {narrow: isMobileTreeExpanded, regular: false},
    isTreeExpanded,
    isMobileTreeExpanded,
    expandTree,
    collapseTree,
    treeToggleElement,
    treeToggleRef,
  }
}
