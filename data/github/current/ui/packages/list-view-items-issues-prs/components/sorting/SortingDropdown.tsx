import {EMOJI_MAP, type ReactionContent} from '@github-ui/reaction-viewer/ReactionGroupsUtils'
import {SortAscIcon, SortDescIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {useNavigate} from '@github-ui/use-navigate'

import {LABELS} from '../../constants/labels'
import {parseQuery, replaceSortInQuery} from '../../utils/query'

import styles from './sorting-dropdown.module.css'

const SORT_KEY_MATCHING_REGEX = /(created|updated|comments|reactions|relevance?)/
const SORT_DIRECTION_ICONS = {
  asc: SortAscIcon,
  desc: SortDescIcon,
}
export const SORT_KEY_TO_OPTION_DISPLAY_VALUE = {
  ...LABELS.sortDropdownOptionDisplayValues,
  ...LABELS.sortDropdownReactionLabels,
  reactions: LABELS.totalReactions,
}

type SortingDirection = 'asc' | 'desc'
type SortKey = keyof typeof SORT_KEY_TO_OPTION_DISPLAY_VALUE

export type SortingDropdownProps = {
  activeSearchQuery: string
  dirtySearchQuery: string | null
  setReactionEmojiToDisplay: (arg: {reaction: string; reactionEmoji: string}) => void
  setSortingItemSelected: (arg: string) => void
  searchUrl: (query?: string) => string
  setCurrentPage: (page: number) => void
  nested?: boolean
}

export function SortingDropdown({
  activeSearchQuery,
  dirtySearchQuery,
  setReactionEmojiToDisplay,
  setSortingItemSelected,
  searchUrl,
  setCurrentPage,
  nested = false,
}: SortingDropdownProps) {
  const sortQuery = useMemo(() => parseQuery(activeSearchQuery).get('sort')?.[0] || '', [activeSearchQuery])

  const [direction, setDirection] = useState<SortingDirection>(() => getDirectionFromQuery(sortQuery))
  const [selectedOptionKey, setSelectedOptionKey] = useState<SortKey | null>(() => getSortOptionKeyFromQuery(sortQuery))

  const navigate = useNavigate()

  const updateQuery = useCallback(
    (key: SortKey, sortDirection: SortingDirection) => {
      const queryText = replaceSortInQuery(dirtySearchQuery || '', `${LABELS.sortKeyToQuery[key]}-${sortDirection}`)
      const url = searchUrl(queryText)
      navigate(url)
      setCurrentPage(1)
    },
    [dirtySearchQuery, navigate, searchUrl, setCurrentPage],
  )

  const updateReaction = useCallback(
    (sortKey: SortKey) => {
      const reactionEmojiText = handleEmojiMapValue(sortKey)
      const reactionEmoji = EMOJI_MAP[reactionEmojiText || '']

      if (reactionEmojiText && reactionEmoji) {
        setSortingItemSelected(sortKey)
        setReactionEmojiToDisplay({
          reaction: reactionEmojiText,
          reactionEmoji,
        })
      }
    },
    [setReactionEmojiToDisplay, setSortingItemSelected],
  )

  const onSelectOption = useCallback(
    (value: string, key: SortKey) => {
      setSortingItemSelected(value)

      if (key === 'relevance' && direction === 'asc') {
        setDirection('desc')
        updateQuery(key, 'desc')
      } else {
        updateQuery(key, direction)
      }
    },
    [direction, updateQuery, setSortingItemSelected],
  )

  const onSelectReactions = useCallback(
    (key: SortKey) => {
      if (direction === 'asc') {
        setDirection('desc')
      }
      updateQuery(key, 'desc')
      updateReaction(key)
    },
    [direction, updateQuery, updateReaction],
  )

  const onSelectDirection = useCallback(
    (value: SortingDirection) => {
      if (selectedOptionKey) {
        setDirection(value)
        setSortingItemSelected(SORT_KEY_TO_OPTION_DISPLAY_VALUE[selectedOptionKey])
        updateQuery(selectedOptionKey, value)
      }
    },
    [updateQuery, selectedOptionKey, setSortingItemSelected],
  )

  useEffect(() => {
    setDirection(getDirectionFromQuery(sortQuery))
    setSelectedOptionKey(getSortOptionKeyFromQuery(sortQuery))

    const selectedKey = getSelectedSortOptionKeyFromQuery(sortQuery)
    setSortingItemSelected(selectedKey)
    updateReaction(selectedKey)
  }, [setReactionEmojiToDisplay, setSortingItemSelected, sortQuery, updateReaction])

  const sortingLabelKeyValuePairs = Object.entries(LABELS.sortDropdownOptionDisplayValues) as Array<[SortKey, string]>
  const sortingEmojiKeyValuePairs = Object.entries(LABELS.sortDropdownReactionLabels) as Array<[SortKey, string]>
  const disableDirection = isEmojiSelected(selectedOptionKey) || selectedOptionKey === 'relevance'

  const secondaryReactionMenu = (
    <ActionList.Group selectionVariant="single">
      <ActionList.Item
        key="reactions"
        onSelect={() => onSelectOption(LABELS.totalReactions, 'reactions')}
        selected={selectedOptionKey === 'reactions'}
        aria-label={getAriaLabel('reactions', direction)}
        role="menuitemradio"
      >
        {LABELS.totalReactions}
      </ActionList.Item>
      <ActionList.Divider />
      {sortingEmojiKeyValuePairs.map(([sortKey, displayValue]) => (
        <ActionList.Item
          key={sortKey}
          onSelect={() => onSelectReactions(sortKey)}
          selected={selectedOptionKey === sortKey}
          aria-label={getAriaLabel(sortKey, 'desc')}
          role="menuitemradio"
        >
          <ActionList.LeadingVisual>{EMOJI_MAP[handleEmojiMapValue(sortKey) || '']}</ActionList.LeadingVisual>
          {displayValue}
        </ActionList.Item>
      ))}
    </ActionList.Group>
  )

  const primaryMenu = (
    <>
      {sortingLabelKeyValuePairs.map(([sortKey, displayValue]) => (
        <ActionList.Item
          key={sortKey}
          onSelect={() => onSelectOption(displayValue, sortKey)}
          selected={selectedOptionKey === sortKey}
          aria-label={getAriaLabel(sortKey, direction)}
          role="menuitemradio"
        >
          {displayValue}
        </ActionList.Item>
      ))}
      <ActionMenu>
        <ActionMenu.Anchor>
          <ActionList.Item selected={isEmojiSelected(selectedOptionKey) || selectedOptionKey === 'reactions'}>
            {LABELS.reactions}
          </ActionList.Item>
        </ActionMenu.Anchor>

        <ActionMenu.Overlay>
          <ActionList selectionVariant="single">{secondaryReactionMenu}</ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <>
        <ActionList.Divider />
        <ActionList.Item
          disabled={disableDirection}
          key="ascending"
          selected={direction === 'asc' && selectedOptionKey !== null}
          onSelect={() => onSelectDirection('asc')}
          aria-label={getDirectionLabel(selectedOptionKey, 'asc')}
        >
          <ActionList.LeadingVisual>
            <SortAscIcon />
          </ActionList.LeadingVisual>
          {getDirectionLabel(selectedOptionKey, 'asc')}
        </ActionList.Item>
        <ActionList.Item
          disabled={disableDirection}
          key="descending"
          selected={direction === 'desc' && selectedOptionKey !== null}
          onSelect={() => onSelectDirection('desc')}
          aria-label={getDirectionLabel(selectedOptionKey, 'desc')}
        >
          <ActionList.LeadingVisual>
            <SortDescIcon />
          </ActionList.LeadingVisual>
          {getDirectionLabel(selectedOptionKey, 'desc')}
        </ActionList.Item>
      </>
    </>
  )

  if (nested)
    return (
      <>
        <ActionList.Group selectionVariant="single">
          <ActionList.GroupHeading>{LABELS.sortBy}</ActionList.GroupHeading>
          {primaryMenu}
        </ActionList.Group>
      </>
    )

  return (
    <ActionMenu>
      <ActionMenu.Button
        variant="invisible"
        className={styles.sortingMenuButton}
        leadingVisual={SORT_DIRECTION_ICONS[direction || 'desc']}
      >
        {selectedOptionKey ? getSortOptionButtonLabel(selectedOptionKey, direction || 'desc') : LABELS.sort}
      </ActionMenu.Button>

      <ActionMenu.Overlay>
        <ActionList selectionVariant="single">{primaryMenu}</ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

export function getSelectedSortOptionKeyFromQuery(query: string): SortKey {
  const sortKey = getSortOptionKeyFromQuery(query)

  // Default to `relevance` if the sort key is not valid
  // because results are sorted by relevance in this case.
  if (!sortKey) {
    return 'relevance'
  }

  return sortKey
}

export function handleEmojiMapValue(sortKey: SortKey): ReactionContent | undefined {
  const emoji = SORT_KEY_TO_OPTION_DISPLAY_VALUE[sortKey]?.replace(' ', '_').toUpperCase()
  return isValidEmoji(emoji) ? emoji : undefined
}

function getDirectionFromQuery(query: string): SortingDirection {
  const direction = query.split('-')?.[1]

  if (direction === 'asc' || direction === 'desc') {
    return direction as SortingDirection
  }

  return 'desc'
}

function getSortOptionKeyFromQuery(query: string): SortKey | null {
  if (!query) {
    return 'created'
  }

  let key = query.match(SORT_KEY_MATCHING_REGEX)?.[0]

  if (key === 'reactions') {
    key = query.split(/-asc|-desc/)?.[0]?.split('reactions-')?.[1] || 'reactions'
  }

  return isValidSortKey(key) ? key : null
}

function getSortOptionButtonLabel(sortKey: SortKey, direction: SortingDirection): string {
  if (sortKey === 'created') {
    return LABELS.sortDropdownMenuButtonLabels[sortKey][direction]
  }

  return LABELS.sortDropdownMenuButtonLabels[sortKey]
}

function getDirectionLabel(sortKey: SortKey | null, direction: SortingDirection): string {
  if (sortKey === 'created' || sortKey === 'updated') {
    return direction === 'asc' ? LABELS.Oldest : LABELS.Newest
  }

  return direction === 'asc' ? LABELS.ascending : LABELS.descending
}

function getAriaLabel(sortKey: SortKey | null, direction: SortingDirection): string {
  if (!sortKey || !direction) {
    return ''
  }
  return `${LABELS.sortBy} ${LABELS.sortKeyToAriaLabel[sortKey]} ${getDirectionLabel(sortKey, direction).toLowerCase()}`
}

function isEmojiSelected(sortKey: SortKey | null): boolean {
  return sortKey ? LABELS.sortDropdownReactionLabels.hasOwnProperty(sortKey) : false
}

function isValidSortKey(sortKey: string | undefined): sortKey is SortKey {
  if (!sortKey) {
    return false
  }

  return Object.keys(SORT_KEY_TO_OPTION_DISPLAY_VALUE).includes(sortKey)
}

function isValidEmoji(emoji: string): emoji is ReactionContent {
  return Object.keys(EMOJI_MAP).includes(emoji)
}
