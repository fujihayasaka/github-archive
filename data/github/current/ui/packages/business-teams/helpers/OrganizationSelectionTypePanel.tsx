import {useState} from 'react'
import {ActionList, Label} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {TasklistIcon, OrganizationIcon, TriangleDownIcon, CircleSlashIcon} from '@primer/octicons-react'

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
  const [isSelectPanelOpen, setSelectPanelOpen] = useState(false)
  const allOrganizationsCountBelowLimit = allOrgsCount <= enterpriseTeamsOrgAssignmentLimit
  const options = [
    {
      icon: <OrganizationIcon />,
      title: 'All organizations',
      description: 'This applies to all current and future organizations.',
      id: 'all',
      value: 'all',
      disabled: !canSelectAllOrganizations || !allOrganizationsCountBelowLimit,
      inactiveText: !canSelectAllOrganizations
        ? 'This selection type is not yet supported.'
        : (!allOrganizationsCountBelowLimit &&
            `Selection type is not available because a maximum of ${enterpriseTeamsOrgAssignmentLimit} organizations can be selected, but this Enterprise has ${allOrgsCount} organizations.`) ||
          undefined,
    },
    {
      icon: <TasklistIcon />,
      title: 'Specific organizations',
      description: `Select at least one organization. Max ${enterpriseTeamsOrgAssignmentLimit} organizations.`,
      id: 'selected',
      value: 'selected',
    },
    {
      icon: <CircleSlashIcon />,
      title: 'None',
      description: 'Your team will not have any organizations access.',
      id: 'disabled',
      value: 'disabled',
    },
  ]

  function handleSelectionChange(type: string) {
    onSelectionChange(type)
    setSelectPanelOpen(false)
  }

  return (
    <>
      <SelectPanel title="Select organization type" open={isSelectPanelOpen} onCancel={() => setSelectPanelOpen(false)}>
        <SelectPanel.Button trailingAction={TriangleDownIcon} onClick={() => setSelectPanelOpen(!isSelectPanelOpen)}>
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
        </SelectPanel.Button>
        <ActionList selectionVariant="single" showDividers role="menu">
          {options.map(option => (
            <ActionList.Item
              key={option.id}
              role="menuitemradio"
              inactiveText={option.disabled ? option.inactiveText : undefined}
              selected={selectionType === option.value}
              aria-checked={selectionType === option.value}
              onSelect={() => handleSelectionChange(option.value)}
            >
              <ActionList.LeadingVisual>{option.icon}</ActionList.LeadingVisual>
              {option.title}
              <ActionList.Description variant="block">{option.description}</ActionList.Description>
            </ActionList.Item>
          ))}
        </ActionList>
      </SelectPanel>
    </>
  )
}
