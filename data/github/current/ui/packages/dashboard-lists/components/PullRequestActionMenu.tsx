import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {useAnalytics} from '@github-ui/use-analytics'
import {isStaff} from '@github-ui/stats'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Link, Text} from '@primer/react'
import {useState} from 'react'
import styles from '../DashboardLists.module.css'
import {PullRequestQueryQualifier} from '../types'

const menuItems = [
  {label: 'Authored', value: PullRequestQueryQualifier.Authored},
  {label: 'Mentioned', value: PullRequestQueryQualifier.Mentions},
  {label: 'Review requested', value: PullRequestQueryQualifier.ReviewRequested},
  {label: 'Reviewed', value: PullRequestQueryQualifier.ReviewedBy},
]

export const RESULT_COUNTS = [3, 6, 9, 12]

export interface PullRequestActionMenuProps {
  setPullRequestQueryQualifiers: (queries: PullRequestQueryQualifier[]) => void
  selectedPullRequestQueryQualifiers: PullRequestQueryQualifier[]
  setPullRequestResultCount: (count: number) => void
  initialResultCount: number
}

export function PullRequestActionMenu({
  setPullRequestQueryQualifiers,
  selectedPullRequestQueryQualifiers,
  setPullRequestResultCount,
  initialResultCount,
}: PullRequestActionMenuProps) {
  const userIsStaff = isStaff()
  const findIndices = (): Set<number> => {
    return new Set(
      selectedPullRequestQueryQualifiers.map(qualifer => menuItems.findIndex(item => item.value === qualifer)),
    )
  }
  const [selectedIndices, setSelectedIndices] = useState<Set<number>>(() => findIndices())
  const [open, setOpen] = useState<boolean>(false)
  const {sendAnalyticsEvent} = useAnalytics()
  const [currentResultCount, setCurrentResultCount] = useState<number>(initialResultCount)

  const handleSelect = (index: number): void => {
    const newSelectedIndices = new Set(selectedIndices)
    if (selectedIndices.has(index)) {
      newSelectedIndices.delete(index)
    } else {
      newSelectedIndices.add(index)
    }
    setSelectedIndices(newSelectedIndices)
  }

  const handleOpenChange = (isOpen: boolean) => {
    setOpen(isOpen)

    if (!isOpen) {
      const queryQualifiers = Array.from(selectedIndices)
        .filter(index => index >= 0 && index < menuItems.length)
        .map(index => menuItems[index]?.value)
        // We shouldn't need this but TypeScript doesn't know that the index is valid
        .filter(value => value !== undefined)

      setPullRequestQueryQualifiers(queryQualifiers)
      setPullRequestResultCount(currentResultCount)

      sendAnalyticsEvent('pull_request_options.save', 'DASHBOARD_PULL_REQUEST_ACTION_MENU', {
        filters: queryQualifiers.join(','),
        category: 'productivity_dashboard',
        result_count: currentResultCount.toString(),
      })
    }
  }

  return (
    <ActionMenu open={open} onOpenChange={handleOpenChange}>
      <ActionMenu.Anchor>
        <IconButtonWithTooltip
          icon={KebabHorizontalIcon}
          variant="invisible"
          label="Pull request options"
          tooltipDirection="w"
          hideTooltip={open}
          className={styles.Muted}
          size="small"
          data-testid="pull-request-filter-menu-button"
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="small" align="end" data-testid="pull-request-filter-menu-overlay">
        <ActionList role="menu">
          <ActionList.Group selectionVariant="multiple">
            <ActionList.GroupHeading>Pull requests to include</ActionList.GroupHeading>
            {menuItems.map((item, index) => (
              <ActionList.Item
                disabled={item.value === 'author'}
                key={item.value}
                role="menuitemcheckbox"
                selected={selectedIndices.has(index)}
                aria-checked={selectedIndices.has(index)}
                aria-disabled={item.value === 'author'}
                onSelect={e => {
                  e.preventDefault() // Prevent ActionMenu from closing on select
                  handleSelect(index)
                }}
              >
                {item.label}
              </ActionList.Item>
            ))}
          </ActionList.Group>
          <ActionList.Divider />

          <ActionList.Group selectionVariant="single">
            <ActionList.GroupHeading>Number of results</ActionList.GroupHeading>
            {RESULT_COUNTS.map(count => (
              <ActionList.Item
                key={count}
                role="menuitemradio"
                selected={currentResultCount === count}
                aria-checked={currentResultCount === count}
                onSelect={e => {
                  e.preventDefault() // Prevent ActionMenu from closing on select
                  setCurrentResultCount(count)
                }}
              >
                {count}
              </ActionList.Item>
            ))}
          </ActionList.Group>

          {userIsStaff ? (
            <>
              <ActionList.Divider />
              <Text as="p" size="small" className="fgColor-muted my-3 mx-3">
                Help give feature preview feedback in this{' '}
                <Link href="https://gh.io/pr-module-feedback" inline target="_blank">
                  discussion post
                </Link>
                .
              </Text>
            </>
          ) : null}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
