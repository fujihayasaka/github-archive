import {useState} from 'react'
import {SelectPanel, Label, Button} from '@primer/react'
import {TasklistIcon, OrganizationIcon, TriangleDownIcon, CircleSlashIcon} from '@primer/octicons-react'

import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'

interface OrganizationSelectionTypePanelProps {
  selectionType: string
  selectedOrganizationCount: number
  allOrgsCount: number
  canSelectAllOrganizations: boolean
  enterpriseTeamsOrgAssignmentLimit: number
  onSelectionChange: (selectionType: string) => void
}

export function OrganizationSelectionTypePanel({
  selectionType,
  selectedOrganizationCount,
  allOrgsCount,
  canSelectAllOrganizations,
  enterpriseTeamsOrgAssignmentLimit,
  onSelectionChange,
}: OrganizationSelectionTypePanelProps) {
  const [isSelectPanelOpen, setIsSelectPanelOpen] = useState(false)
  const [filter, setFilter] = useState('')

  const allOrganizationsCountBelowLimit = allOrgsCount <= enterpriseTeamsOrgAssignmentLimit
  const items: ItemInput[] = [
    {
      leadingVisual: () => <OrganizationIcon />,
      text: !canSelectAllOrganizations
        ? 'This selection type is not yet supported.'
        : (!allOrganizationsCountBelowLimit &&
            `Selection type is not available because a maximum of ${enterpriseTeamsOrgAssignmentLimit} organizations can be selected, but this Enterprise has ${allOrgsCount} organizations.`) ||
          'All organizations',
      description: 'This applies to all current and future organizations.',
      descriptionVariant: 'block',
      id: 'all',
      disabled: !canSelectAllOrganizations || !allOrganizationsCountBelowLimit,
    },
    {
      leadingVisual: () => <TasklistIcon />,
      text: 'Specific organizations',
      description: `Select at least one organization. Max ${enterpriseTeamsOrgAssignmentLimit} organizations.`,
      descriptionVariant: 'block',
      id: 'selected',
    },
    {
      leadingVisual: () => <CircleSlashIcon />,
      text: 'None',
      description: 'Your team will not have any organizations access.',
      descriptionVariant: 'block',
      id: 'disabled',
    },
  ]

  const filteredItems = items.filter(
    item => item.id === selectionType || item.text?.toLowerCase().startsWith(filter.toLowerCase()),
  )

  return (
    // eslint-disable-next-line primer-react/no-system-props
    <SelectPanel
      renderAnchor={({children, ...anchorProps}) => (
        <Button {...anchorProps} trailingAction={TriangleDownIcon} aria-haspopup="dialog">
          {selectionType === 'all' ? (
            <span>
              <OrganizationIcon className="mr-2" />
              All organizations
              <Label variant="default" className="ml-2 mr-1">
                {selectedOrganizationCount}
              </Label>
            </span>
          ) : selectionType === 'selected' ? (
            <span>
              <TasklistIcon className="mr-2" />
              Specific organizations
              <Label variant="default" className="ml-2 mr-1">
                {selectedOrganizationCount}
              </Label>
            </span>
          ) : (
            <span className="mr-1">None</span>
          )}
        </Button>
      )}
      title="Select organization type"
      items={filteredItems}
      showItemDividers
      open={isSelectPanelOpen}
      onOpenChange={setIsSelectPanelOpen}
      selected={items.find(item => item.id === selectionType)}
      onSelectedChange={(newSelected: ItemInput | undefined) => {
        if (newSelected && newSelected.id) {
          onSelectionChange(`${newSelected.id}`)
        }
      }}
      onFilterChange={setFilter}
      width="medium"
      onCancel={() => setIsSelectPanelOpen(false)}
    />
  )
}
