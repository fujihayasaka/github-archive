// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {isSearchUrl} from '@github-ui/code-view-shared/components/files-search/FilesSearchBox'
import {useReposAnalytics} from '@github-ui/code-view-shared/hooks/use-repos-analytics'
import type {CollapseTreeFunction, ExpandTreeFunction} from '@github-ui/code-view-types'
import {getCookie, setCookie} from '@github-ui/cookies'
import {useCurrentUser} from '@github-ui/current-user'
// eslint-disable-next-line no-restricted-imports
import {ScreenSize, useScreenSize} from '@github-ui/screen-size'
import {ssrSafeDocument} from '@github-ui/ssr-utils'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {Heading} from '@primer/react'
import {useCallback, useMemo, useRef, useState} from 'react'

import {ExpandFileTreeButton, type ExpandFileTreeButtonProps} from '../components/ExpandFileTreeButton'
import {TreeOverlayBreakpoint} from '../components/ReposFileTreePane'
import styles from './use-tree-pane.module.css'

export interface TreePane {
  isTreeExpanded: boolean
  treeToggleElement: JSX.Element
  treeToggleRef: React.RefObject<HTMLButtonElement>
  searchBoxRef: React.RefObject<HTMLInputElement>
  expandTree: ExpandTreeFunction
  collapseTree: CollapseTreeFunction
}

export function useTreePane(
  reposFileTreeId: string,
  openPanelRef: React.MutableRefObject<string | undefined>,
  treeExpanded: boolean,
  textAreaId: string,
  updateExpandPreferences?: (expanded: boolean) => void,
  cookieName = 'fileTreeExpanded',
  expandFileTreeButtonProps?: Partial<ExpandFileTreeButtonProps>,
): TreePane {
  const {sendRepoClickEvent} = useReposAnalytics()
  const currentUser = useCurrentUser()

  const fileTreeExpandedCookie = cookieName ? getCookie(cookieName) : undefined
  const isSSR = !!(typeof ssrSafeDocument === 'undefined')
  // Only use the cookie if the user isn't logged in
  let initiallyExpanded =
    (!currentUser && fileTreeExpandedCookie && fileTreeExpandedCookie.value !== 'false') ||
    (currentUser && treeExpanded)

  if (initiallyExpanded === undefined) {
    initiallyExpanded = false
  }

  const treeToggleRef = useRef<HTMLButtonElement>(null)
  const searchBoxRef = useRef<HTMLInputElement>(null)
  const {screenSize} = useScreenSize()

  const [isTreeExpanded, setIsTreeExpanded] = useState(initiallyExpanded)
  // Keep track of the last state that was specifically requested by the user
  const lastStateIsExpanded = useRef(initiallyExpanded)
  const expandTreeCookieExpiration = 30 * 24 * 60 * 60 * 1000 // 30 days
  const expandedAsOverlay = useRef(false)
  const hasManuallyCollapsed = useRef(false)

  const showAsOverlay = useCallback(() => {
    return !(
      (openPanelRef.current && window.innerWidth >= TreeOverlayBreakpoint) ||
      (!openPanelRef.current && window.innerWidth >= ScreenSize.xlarge)
    )
  }, [openPanelRef])

  /**
   * With SSR, we need to make sure we get the correct initial state for the tree
   */
  useLayoutEffect(() => {
    const showingAsOverlay = showAsOverlay()
    if (!showingAsOverlay) {
      expandedAsOverlay.current = false
    }
    const shouldExpand =
      (isSearchUrl() && screenSize < ScreenSize.large && !hasManuallyCollapsed.current) ||
      ((!showingAsOverlay || expandedAsOverlay.current) &&
        ((currentUser && isTreeExpanded) || (!currentUser && fileTreeExpandedCookie?.value !== 'false')))
    setIsTreeExpanded(shouldExpand)
    // Don't retrigger when the tree expanded state changes.
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expandedAsOverlay, fileTreeExpandedCookie?.value, screenSize, openPanelRef, showAsOverlay, currentUser])

  /**
   * When the screen size shrinks below medium, collapse the tree if it is expanded.
   * When the screen size grows beyond medium, return the tree to its last state.
   */
  useLayoutEffect(() => {
    const shouldClose = !openPanelRef.current && window.innerWidth < ScreenSize.xlarge
    const shouldOpen = !openPanelRef.current && window.innerWidth >= ScreenSize.xlarge
    if (shouldClose && lastStateIsExpanded.current && !isSearchUrl() && isTreeExpanded) {
      setIsTreeExpanded(false)
    }

    if (shouldOpen && lastStateIsExpanded.current && !isTreeExpanded) {
      setIsTreeExpanded(true)
    }
    // Don't retrigger when the tree expanded state changes.
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [openPanelRef, screenSize])

  /**
   * When the screen size shrinks below large, collapse the tree if it is expanded.
   * When the screen size grows beyond large, return the tree to its last state.
   */
  useLayoutEffect(() => {
    const shouldClose = openPanelRef.current && window.innerWidth < TreeOverlayBreakpoint
    const shouldOpen = openPanelRef.current && window.innerWidth >= TreeOverlayBreakpoint
    if (shouldClose && lastStateIsExpanded.current && !isSearchUrl() && isTreeExpanded) {
      setIsTreeExpanded(false)
    }
    if (shouldOpen && lastStateIsExpanded.current && !isTreeExpanded) {
      setIsTreeExpanded(true)
    }
    // Don't retrigger when the tree expanded state changes.
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [openPanelRef])

  const expandTree: ExpandTreeFunction = useCallback(
    options => {
      setIsTreeExpanded(true)
      if (showAsOverlay()) {
        expandedAsOverlay.current = true
      }

      if (options?.setPreference) {
        updateExpandPreferences?.(true)
        lastStateIsExpanded.current = true
        if (cookieName) {
          const expireTime = new Date(Date.now() + expandTreeCookieExpiration).toUTCString()
          setCookie(cookieName, 'true', expireTime)
        }
      }

      if (options?.focus === 'toggleButton') {
        requestAnimationFrame(() => treeToggleRef.current?.focus())
      } else if (options?.focus === 'search') {
        requestAnimationFrame(() => searchBoxRef.current?.focus())
      }
    },
    [cookieName, expandTreeCookieExpiration, showAsOverlay, updateExpandPreferences],
  )

  const collapseTree: CollapseTreeFunction = useCallback(
    options => {
      setIsTreeExpanded(false)
      expandedAsOverlay.current = false
      hasManuallyCollapsed.current = true
      if (options?.setPreference) {
        updateExpandPreferences?.(false)
        lastStateIsExpanded.current = false
        if (cookieName) {
          const expireTime = new Date(Date.now() + expandTreeCookieExpiration).toUTCString()
          setCookie(cookieName, 'false', expireTime)
        }
      }

      if (options?.focus === 'toggleButton') {
        requestAnimationFrame(() => treeToggleRef.current?.focus())
      }
    },
    [cookieName, expandTreeCookieExpiration, updateExpandPreferences],
  )

  // This is SSR safe since it won't be called during SSR
  const shouldSetPreference = useCallback(
    (openPanel: string | undefined) => {
      return (
        (openPanel && window.innerWidth >= TreeOverlayBreakpoint) ||
        (!openPanelRef.current && window.innerWidth >= ScreenSize.xlarge)
      )
    },
    [openPanelRef],
  )

  const treeToggleElement = useMemo(
    () => (
      <Heading as="h2" className={styles.Heading}>
        <ExpandFileTreeButton
          expanded={isTreeExpanded}
          ariaControls={reposFileTreeId}
          onToggleExpanded={() => {
            sendRepoClickEvent(isTreeExpanded ? 'FILES_TREE.HIDE' : 'FILES_TREE.SHOW')
            // On the overview page, the toggle button isn't sticky, we don't want the user to lose the place
            // on the page to focuss it if they click
            if (isTreeExpanded) {
              collapseTree({
                focus: 'toggleButton',
                setPreference: shouldSetPreference(openPanelRef.current),
              })
            } else {
              expandTree({focus: 'toggleButton', setPreference: shouldSetPreference(openPanelRef.current)})
            }
          }}
          className={
            fileTreeExpandedCookie === undefined && !isTreeExpanded && !isSSR
              ? 'react-tree-toggle-button-with-indicator'
              : undefined
          }
          ref={treeToggleRef}
          textAreaId={textAreaId}
          {...expandFileTreeButtonProps}
        />
      </Heading>
    ),
    [
      isTreeExpanded,
      reposFileTreeId,
      fileTreeExpandedCookie,
      isSSR,
      textAreaId,
      expandFileTreeButtonProps,
      sendRepoClickEvent,
      collapseTree,
      shouldSetPreference,
      openPanelRef,
      expandTree,
    ],
  )

  return {
    isTreeExpanded,
    expandTree,
    collapseTree,
    treeToggleElement,
    treeToggleRef,
    searchBoxRef,
  }
}
