import {usePortalTooltip} from '@github-ui/portal-tooltip/use-portal-tooltip'
import {testIdProps} from '@github-ui/test-id-props'
import {FocusKeys} from '@primer/behaviors'
import {ChevronLeftIcon, ChevronRightIcon, SlidersIcon, ZoomInIcon} from '@primer/octicons-react'
import {
  ActionList,
  ActionMenu,
  type BetterSystemStyleObject,
  Box,
  Button,
  IconButton,
  Popover,
  Text,
  useFocusZone,
} from '@primer/react'
import {memo, useId, useMemo, useRef, useState} from 'react'

import {
  RoadmapDateFieldsPopoverDismissed,
  RoadmapDateFieldsUIPopover,
  ViewOptionsToolbarUI,
} from '../../../api/stats/contracts'
import {getDateFieldToolbarStatsContext} from '../../../api/stats/helpers'
import {ViewTypeParam} from '../../../api/view/contracts'
import {PotentiallyDirty} from '../../../components/potentially-dirty'
import {RoadmapDateFieldsMenu} from '../../../components/roadmap/roadmap-date-fields-menu'
import {MarkerDirtyIcon, RoadmapMarkerMenu} from '../../../components/roadmap/roadmap-marker-menu'
import {RoadmapZoomLevelMenu} from '../../../components/roadmap/roadmap-zoom-level-menu'
import {SortByMenu} from '../../../components/sort-by-menu'
import {optionsForRoadmapToolbar} from '../../../components/view-options/configuration'
import {RoadmapDateFieldsDirtyIcon, SortLeadingVisual} from '../../../components/view-options/icons'
import {useRoadmapDateFieldsMenu} from '../../../features/roadmap/roadmap-date-fields-menu'
import {isRoadmapColumnModel} from '../../../helpers/roadmap-helpers'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import {usePrefixedId} from '../../../hooks/common/use-prefixed-id'
import {useRoadmapSessionSettings, useRoadmapSettings, useRoadmapZoomLevel} from '../../../hooks/use-roadmap-settings'
import {useRoadmapTableIsNarrow} from '../../../hooks/use-roadmap-table-is-narrow'
import {useSortedBy} from '../../../hooks/use-sorted-by'
import {ViewOptionsStatsUiContext} from '../../../hooks/use-view-options-stats-ui-key'
import {useViews} from '../../../hooks/use-views'
import {RoadmapResources} from '../../../strings'
import {useRoadmapNavigation, useRoadmapView} from '../roadmap-view-provider'
import {ROADMAP_CONTROLS_Z_INDEX} from '../roadmap-z-index'

const buttonStyles = {
  color: 'fg.muted',
  fontWeight: 'normal',
}

const roadmapControlsStyles: BetterSystemStyleObject = {
  position: 'absolute',
  top: '3px',
  right: 3,
  zIndex: ROADMAP_CONTROLS_Z_INDEX,
  pr: [0, 2, 3],
  my: 0,
  '&:before': {
    content: '""',
    position: 'absolute',
    top: 0,
    left: '-20px',
    width: '20px',
    height: '100%',
    backgroundColor: 'canvas.default',
    // Opacity gradient from left to right to slowly add more of the background color.
    maskImage: 'linear-gradient(to right, rgba(255, 255, 255, 0) 0%, rgba(255, 255, 255, 1) 100%)',
  },
  display: 'flex',
  flexDirection: 'row',
  alignItems: 'center',
  backgroundColor: 'canvas.default',
  listStyle: 'none',
}

/** Roadmap header controls including navigation, zoom level, and other options */
export const RoadmapControls = memo(function RoadmapControls() {
  const containerRef = useRef<HTMLUListElement>(null)
  useFocusZone({
    containerRef,
    bindKeys: FocusKeys.ArrowHorizontal,
  })
  const {isTableNarrow} = useRoadmapTableIsNarrow()

  return (
    <Box role="menubar" ref={containerRef} as="ul" sx={roadmapControlsStyles} {...testIdProps(`quick-action-toolbar`)}>
      <ViewOptionsStatsUiContext.Provider value={ViewOptionsToolbarUI}>
        {!isTableNarrow && (
          <>
            <RoadmapMarkerButton />
            <RoadmapSortByMenu />
            <DateConfigurationMenu />
            <ZoomLevelMenu />
          </>
        )}
        {isTableNarrow && <RoadmapCondensedOptions />}
        <TodayButton />
        <PrevPageButton />
        <NextPageButton />
      </ViewOptionsStatsUiContext.Provider>
    </Box>
  )
})

const RoadmapCondensedOptions = () => {
  const id = useId()
  const anchorRef = useRef<HTMLButtonElement>(null)
  const submenuRef = useRef<HTMLLIElement>(null)

  const [isOpen, setOpen] = useState(false)
  const [submenu, setSubmenu] = useState<string | null>(null)

  const {isSortedByDirty} = useSortedBy()
  const {isRoadmapMarkerFieldsDirty, isRoadmapZoomLevelDirty, isRoadmapDateFieldsDirty} = useRoadmapSettings()
  const showDirtyState =
    isSortedByDirty || isRoadmapMarkerFieldsDirty || isRoadmapZoomLevelDirty || isRoadmapDateFieldsDirty
  const {hasWritePermissions} = ViewerPrivileges()

  const getAnchor = (name: string) => {
    // Allow anchoring the "Add Field" overlay to the menu anchor
    if (name === 'Dates' && submenu !== 'Dates') {
      return anchorRef
    }
    return submenuRef
  }

  return (
    <>
      <li role="menuitem">
        <PotentiallyDirty
          {...testIdProps('quick-action-toolbar-options-dirty')}
          isDirty={showDirtyState}
          hideDirtyState={!hasWritePermissions}
        >
          <IconButton
            aria-label={RoadmapResources.toolbarRoadmapOptions}
            ref={anchorRef}
            size="small"
            variant="invisible"
            icon={SlidersIcon}
            onClick={() => setOpen(!isOpen)}
            aria-controls={id}
            aria-expanded={isOpen}
            aria-haspopup="true"
            sx={buttonStyles}
            {...testIdProps('quick-action-toolbar-options-button')}
          />
        </PotentiallyDirty>
      </li>
      <ActionMenu anchorRef={anchorRef} open={isOpen} onOpenChange={nextOpen => setOpen(nextOpen)}>
        <ActionMenu.Overlay width="medium" {...testIdProps('quick-action-toolbar-options-menu')}>
          <ActionList id={id}>
            {optionsForRoadmapToolbar.map(option => (
              <ActionList.Item
                ref={submenu === option.title ? submenuRef : null}
                key={option.title}
                onSelect={e => {
                  setSubmenu(option.title)
                  e.preventDefault()
                }}
              >
                <ActionList.LeadingVisual>
                  <option.icon />
                </ActionList.LeadingVisual>
                <option.TextContent />
                <ActionList.TrailingVisual>
                  <ChevronRightIcon />
                </ActionList.TrailingVisual>
              </ActionList.Item>
            ))}
          </ActionList>
          {optionsForRoadmapToolbar.map(option => (
            <option.MenuComponent
              key={option.title}
              anchorRef={getAnchor(option.title)}
              open={submenu === option.title}
              setOpen={nextOpen => {
                setSubmenu(nextOpen ? option.title : null)
              }}
            />
          ))}
        </ActionMenu.Overlay>
      </ActionMenu>
    </>
  )
}

const RoadmapMarkerButton = () => {
  const id = useId()
  const ref = useRef<HTMLButtonElement>(null)
  const [open, setOpen] = useState(false)
  return (
    <Box as="li" sx={{position: 'relative'}} role="menuitem">
      <Button
        {...testIdProps('quick-action-toolbar-markers-menu')}
        ref={ref}
        aria-haspopup="true"
        aria-expanded={open}
        aria-controls={id}
        trailingVisual={null}
        variant="invisible"
        size="small"
        sx={buttonStyles}
        leadingVisual={MarkerDirtyIcon}
        onClick={() => setOpen(s => !s)}
      >
        Markers
      </Button>
      <ActionMenu anchorRef={ref} open={open}>
        <ActionMenu.Overlay
          role="dialog"
          onEscape={() => setOpen(false)}
          onClickOutside={() => setOpen(false)}
          aria-label="Configure vertical markers to display on roadmap"
        >
          <RoadmapMarkerMenu id={id} />
        </ActionMenu.Overlay>
      </ActionMenu>
    </Box>
  )
}

function TodayButton() {
  const {today} = useRoadmapView()
  const {scrollToDate} = useRoadmapNavigation()
  const handleClick = () => {
    scrollToDate(today, true)
  }
  const button = useRef<HTMLButtonElement>(null)
  const [contentProps, tooltip] = usePortalTooltip({
    contentRef: button,
    'aria-label': RoadmapResources.scrollToDateText(today),
  })
  return (
    <Box as="li" sx={{position: 'relative'}} role="menuitem">
      <Button onClick={handleClick} size="small" variant="invisible" sx={buttonStyles} {...contentProps} ref={button}>
        {RoadmapResources.toolbarToday}
      </Button>
      {tooltip}
    </Box>
  )
}

function PrevPageButton() {
  const {scrollToPrevPage} = useRoadmapNavigation()
  const handleClick = () => {
    scrollToPrevPage(true)
  }

  return (
    <li role="menuitem">
      <IconButton
        tooltipDirection="nw"
        onClick={handleClick}
        size="small"
        variant="invisible"
        aria-label={RoadmapResources.scrollToPreviousPage}
        icon={ChevronLeftIcon}
        sx={buttonStyles}
      />
    </li>
  )
}

function NextPageButton() {
  const {scrollToNextPage} = useRoadmapNavigation()
  const handleClick = () => {
    scrollToNextPage(true)
  }

  return (
    <li role="menuitem">
      <IconButton
        role="menuitem"
        tooltipDirection="nw"
        onClick={handleClick}
        size="small"
        variant="invisible"
        aria-label={RoadmapResources.scrollToNextPage}
        icon={ChevronRightIcon}
        sx={buttonStyles}
      />
    </li>
  )
}

function RoadmapSortByMenu() {
  const {isSorted, sorts} = useSortedBy()
  const anchorRef = useRef<HTMLButtonElement>(null)
  const [open, setOpen] = useState(false)

  const sortByButtonOnClick = () => {
    setOpen(!open)
  }

  const {sortLabel, sortText} = useMemo(() => {
    if (isSorted) {
      return {
        // For example: "Sorted by: Status ascending, Title descending"
        sortLabel: `Sorted by: ${sorts
          .map(sort => `${sort.column.name} ${sort.direction === 'asc' ? 'ascending' : 'descending'}`)
          .join(', ')}`,
        sortText: sorts.map(sort => sort.column.name).join(', '),
      }
    }
    return {
      sortLabel: `No sort applied`,
      sortText: 'Sort',
    }
  }, [isSorted, sorts])

  const menuId = usePrefixedId('quick-action-toolbar-sort-by-menu')

  return (
    <Box as="li" sx={{position: 'relative'}} role="menuitem">
      <Button
        ref={anchorRef}
        aria-haspopup="true"
        aria-expanded={open}
        onClick={sortByButtonOnClick}
        variant="invisible"
        size="small"
        sx={buttonStyles}
        aria-controls={menuId}
        aria-label={sortLabel}
        {...testIdProps('quick-action-toolbar-sort-by-menu')}
      >
        <Box sx={{display: 'flex'}}>
          <SortLeadingVisual />
          <Text sx={{ml: 2}}>{sortText}</Text>
        </Box>
      </Button>

      <SortByMenu id={menuId} anchorRef={anchorRef} open={open} setOpen={setOpen} />
    </Box>
  )
}

function ZoomLevelMenu() {
  const {hasWritePermissions} = ViewerPrivileges()
  const zoomLevel = useRoadmapZoomLevel()
  const {isRoadmapZoomLevelDirty} = useRoadmapSettings()

  const anchorRef = useRef<HTMLButtonElement>(null)
  const [open, setOpen] = useState(false)

  const zoomLevelButtonOnClick = () => {
    setOpen(!open)
  }

  const menuId = usePrefixedId('roadmap-zoom-level-menu')

  return (
    <Box as="li" sx={{position: 'relative'}} role="menuitem">
      <Button
        ref={anchorRef}
        aria-haspopup="true"
        aria-expanded={open}
        onClick={zoomLevelButtonOnClick}
        variant="invisible"
        size="small"
        aria-label={RoadmapResources.toolbarZoomAriaLabel(zoomLevel)}
        sx={buttonStyles}
        aria-controls={menuId}
        {...testIdProps('quick-action-toolbar-zoom-level')}
      >
        <Box sx={{display: 'flex'}}>
          <PotentiallyDirty
            isDirty={isRoadmapZoomLevelDirty}
            hideDirtyState={!hasWritePermissions}
            {...testIdProps('roadmap-zoom-level-dirty')}
          >
            <ZoomInIcon />
          </PotentiallyDirty>
          <Text sx={{ml: 2}}>{RoadmapResources.zoomLevelOptions[zoomLevel]}</Text>
        </Box>
      </Button>

      <RoadmapZoomLevelMenu id={menuId} anchorRef={anchorRef} open={open} setOpen={setOpen} />
    </Box>
  )
}

function DateConfigurationMenu() {
  const {dateFields, areDateFieldsDefault} = useRoadmapSettings()
  const {isDateFieldsPopoverDisabled} = useRoadmapSessionSettings()
  const withoutDuplicates = new Set(dateFields.filter(isRoadmapColumnModel).map(field => field.name))
  const {isDateConfigurationMenuOpen, setOpenDateConfigurationMenu} = useRoadmapDateFieldsMenu()
  const {currentView} = useViews()
  const {postStats} = usePostStats()

  const hasNoDateFields = withoutDuplicates.size === 0
  const isNewRoadmapLayout =
    currentView?.serverViewState.layout !== ViewTypeParam.Roadmap &&
    currentView?.localViewState.layout === ViewTypeParam.Roadmap
  const showInitialSelectedFieldsMessage = !hasNoDateFields && areDateFieldsDefault && isNewRoadmapLayout
  const initialFieldType = dateFields.some(field => isRoadmapColumnModel(field) && field.dataType === 'iteration')
    ? 'iteration'
    : 'date'

  const anchorRef = useRef<HTMLButtonElement>(null)
  const showPopover = !isDateFieldsPopoverDisabled && (hasNoDateFields || showInitialSelectedFieldsMessage)

  const datesButtonOnClick = () => {
    setOpenDateConfigurationMenu(!isDateConfigurationMenuOpen)
  }

  const popoverButtonOnClick = () => {
    setOpenDateConfigurationMenu(true)
    postStats({
      name: RoadmapDateFieldsPopoverDismissed,
      ui: RoadmapDateFieldsUIPopover,
      context: JSON.stringify(getDateFieldToolbarStatsContext(withoutDuplicates.size, initialFieldType)),
    })
  }

  const menuId = usePrefixedId('roadmap-date-fields-menu')

  return (
    <Box as="li" sx={{position: 'relative'}} role="menuitem">
      <Button
        ref={anchorRef}
        aria-haspopup="true"
        aria-expanded={isDateConfigurationMenuOpen}
        onClick={datesButtonOnClick}
        variant="invisible"
        size="small"
        aria-label={RoadmapResources.toolbarDateFieldsAriaLabel}
        sx={buttonStyles}
        aria-controls={menuId}
        {...testIdProps('quick-action-toolbar-date-fields-menu')}
      >
        <Box sx={{display: 'flex'}}>
          <RoadmapDateFieldsDirtyIcon />
          <Text sx={{ml: 2}}>{RoadmapResources.toolbarDateFields}</Text>
        </Box>
      </Button>
      {showPopover && (
        <Popover relative={false} open={showPopover} caret="top" sx={{top: '24px', left: '-54px'}}>
          <Popover.Content sx={{mt: 2}}>
            <Box sx={{fontSize: 2, fontWeight: 'bold'}}>{RoadmapResources.gettingStarted.popoverTitle}</Box>
            <Box sx={{marginTop: 2, marginBottom: 3}}>
              {showInitialSelectedFieldsMessage
                ? RoadmapResources.gettingStarted.fieldsSelectedByDefault(initialFieldType)
                : RoadmapResources.gettingStarted.projectNeedsField}
            </Box>
            <Button onClick={popoverButtonOnClick}>{RoadmapResources.gettingStarted.popoverDismissButton}</Button>
          </Popover.Content>
        </Popover>
      )}
      <RoadmapDateFieldsMenu
        id={menuId}
        anchorRef={anchorRef}
        open={isDateConfigurationMenuOpen}
        setOpen={setOpenDateConfigurationMenu}
      />
    </Box>
  )
}
