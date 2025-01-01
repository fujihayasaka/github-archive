import {LABELS} from '@github-ui/timeline-items/Labels'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, IconButton} from '@primer/react'

type LoadDirectionPickerProps = {
  loadFromTopFn: () => void
  loadFromBottomFn: () => void
  isLoading: boolean
  setIsHovering: (hovering: 'top' | 'bottom' | undefined) => void
  type: 'load-top' | 'load-bottom'
}

export const LoadDirectionPicker = ({
  loadFromTopFn,
  loadFromBottomFn,
  isLoading,
  setIsHovering,
  type,
}: LoadDirectionPickerProps) => (
  <Box sx={{position: 'absolute', alignSelf: 'flex-end'}}>
    <ActionMenu>
      <ActionMenu.Anchor>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton
          unsafeDisableTooltip
          inactive={isLoading}
          aria-disabled={isLoading}
          size="small"
          icon={KebabHorizontalIcon}
          data-testid={`issue-timeline-load-more-options-${type}`}
          variant="invisible"
          aria-label="Load more actions"
          sx={{color: 'fg.muted'}}
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay>
        <ActionList sx={{width: '250px'}}>
          <ActionList.Item
            disabled={isLoading}
            onSelect={loadFromTopFn}
            onMouseEnter={() => setIsHovering('top')}
            onMouseLeave={() => setIsHovering(undefined)}
          >
            <span>{LABELS.timeline.loadOlder}</span>
          </ActionList.Item>
          <ActionList.Item
            disabled={isLoading}
            onSelect={loadFromBottomFn}
            onMouseEnter={() => setIsHovering('bottom')}
            onMouseLeave={() => setIsHovering(undefined)}
          >
            <span>{LABELS.timeline.loadNewer}</span>
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  </Box>
)
