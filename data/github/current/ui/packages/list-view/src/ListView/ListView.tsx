import {noop} from '@github-ui/noop'
import {testIdProps} from '@github-ui/test-id-props'
import {useSyncedState} from '@github-ui/use-synced-state'
import {Heading} from '@primer/react'
import {clsx} from 'clsx'
import {Children, type MutableRefObject, type PropsWithChildren, type ReactElement, useEffect, useMemo} from 'react'

import {defaultVariant} from '../constants'
import {useRovingTabIndex} from '../hooks/use-roving-tab-index'
import type {PrefixedStylableProps} from '../types'
import {IdProvider, useListViewId} from './IdContext'
import {ItemsProvider} from './ItemsContext'
import styles from './ListView.module.css'
import type {ListViewMetadata} from './Metadata'
import {MultiPageSelectionProvider} from './MultiPageSelectionContext'
import {type SelectionContextProps, SelectionProvider} from './SelectionContext'
import {TitleProvider, type TitleProviderProps, useListViewTitle} from './TitleContext'
import {VariantProvider, type VariantType} from './VariantContext'

export type ListViewProps = PropsWithChildren<{
  /**
   * An optional element to contain bulk actions, a 'Select all' checkbox, a density toggle for the view, etc.
   */
  metadata?: ReactElement<typeof ListViewMetadata>
  /**
   * Controls the width and height of the list and its contents
   */
  variant?: VariantType
  /**
   * Callback for when the variant changes
   */
  onVariantChange?: (variant: VariantType) => void
  /**
   * Controls item's selection mode; bulk actions are allowed if true. Defaults to not selectable.
   */
  isSelectable?: boolean
  /**
   * What a single list item should be called. Used to customize assistive text about how many list items are
   * selected. Defaults to 'list item'.
   */
  singularUnits?: string
  /**
   * What many list items are called. Used to customize assistive text about how many list items are selected.
   * Defaults to 'list items'.
   */
  pluralUnits?: string
  /**
   * Optional ID of an element that labels the list view. When provided, this takes the place of the default sr-only title.
   */
  ariaLabelledBy?: string
  className?: string
  listRef?: MutableRefObject<HTMLUListElement | undefined>
  /**
   * Optional property that passes through to the `strict` prop in the useFocusZone hook in @primer/behaviors.
   * When true, performs additional checks to determine tabbability which may adversely affect app performance.
   * Defaults to `true`
   */
  strictFocusZone?: boolean
}> &
  Omit<TitleProviderProps, 'children'> &
  Pick<SelectionContextProps, 'totalCount'> &
  Partial<Pick<SelectionContextProps, 'selectedCount'>> &
  PrefixedStylableProps<'itemsList'>

export const ListView = ({
  title,
  titleHeaderTag,
  children,
  totalCount,
  selectedCount = 0,
  variant: externalVariant = defaultVariant,
  singularUnits,
  pluralUnits,
  onVariantChange = noop,
  isSelectable,
  ...rest
}: PropsWithChildren<ListViewProps>): JSX.Element => {
  const [variant, setVariant] = useSyncedState(externalVariant)

  useEffect(() => {
    onVariantChange?.(variant)
  }, [onVariantChange, variant])

  // eslint-disable-next-line @eslint-react/no-children-to-array
  const countOnPage = useMemo(() => Children.toArray(children).length, [children])

  return (
    <IdProvider>
      <TitleProvider title={title} titleHeaderTag={titleHeaderTag}>
        <VariantProvider variant={variant} setVariant={setVariant}>
          <SelectionProvider
            countOnPage={countOnPage}
            selectedCount={selectedCount}
            totalCount={totalCount}
            singularUnits={singularUnits}
            pluralUnits={pluralUnits}
            isSelectable={isSelectable}
          >
            <MultiPageSelectionProvider>
              <ItemsProvider>
                <ListViewContainer {...rest}>{children}</ListViewContainer>
              </ItemsProvider>
            </MultiPageSelectionProvider>
          </SelectionProvider>
        </VariantProvider>
      </TitleProvider>
    </IdProvider>
  )
}

const ListViewContainer = ({
  metadata,
  children,
  className,
  listRef,
  ariaLabelledBy: externalAriaLabelledBy,
  itemsListClassName,
  itemsListStyle: style,
  strictFocusZone,
  ...rest
}: Omit<ListViewProps, 'title' | 'titleHeaderTag'>): JSX.Element => {
  const {idPrefix} = useListViewId()
  const {title, titleHeaderTag} = useListViewTitle()
  const {containerRef} = useRovingTabIndex(strictFocusZone) as {containerRef: MutableRefObject<HTMLUListElement>}

  useEffect(() => {
    if (listRef) {
      // eslint-disable-next-line react-compiler/react-compiler
      listRef.current = containerRef.current
    }
  }, [containerRef, listRef])

  const listViewContainerTitleId = externalAriaLabelledBy ?? `${idPrefix}-list-view-container-title`

  return (
    <div id={`${idPrefix}-list-view-container`} className={clsx(styles.container, className)}>
      {!externalAriaLabelledBy && (
        <Heading
          className="sr-only"
          as={titleHeaderTag}
          id={listViewContainerTitleId}
          {...testIdProps('list-view-title')}
        >
          {title}
        </Heading>
      )}
      {/**
       * The `metadata` component might have a title rendered in it as well, so there can be some
       * duplication between it and the sr-only list-view-container-title Heading above. However, having that title
       * is important for accessibility and it's better to slightly over-describe than not. The `metadata`
       * section is optional while the title attribute and list-view-container-title that renders it are required.
       */}
      {metadata}
      {/* eslint-disable-next-line jsx-a11y/no-redundant-roles */}
      <ul
        className={clsx(styles.ul, itemsListClassName)}
        style={style}
        ref={containerRef}
        aria-labelledby={listViewContainerTitleId}
        tabIndex={-1}
        // https://ui.githubapp.com/storybook/?path=/docs/recipes-listview-documentation-accessibility-listitem--docs#dom-declarations
        // The role="list" declaration helps enforce the list announcement,
        // which is key to understanding what the ListView's main content is, and how it can be interacted with.
        role="list"
        data-listview-component="items-list"
        {...testIdProps('list-view-items')}
        {...rest}
      >
        {children}
      </ul>
    </div>
  )
}
