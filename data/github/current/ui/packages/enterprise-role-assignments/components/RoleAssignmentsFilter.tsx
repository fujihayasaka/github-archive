import {Filter, type FilterQuery} from '@github-ui/filter'
import {assignmentFilterProviders} from '../utils/filter-utils'
import {testIdProps} from '@github-ui/test-id-props'

interface RoleAssignmentsFilterProps {
  placeholderText: string
  filterValue: string
  onChange: (value: string) => void
  onSubmit: (request: FilterQuery) => void
}

export function RoleAssignmentsFilter({placeholderText, filterValue, onChange, onSubmit}: RoleAssignmentsFilterProps) {
  const providers = assignmentFilterProviders

  return (
    <Filter
      variant="input"
      filterValue={filterValue}
      providers={providers}
      onSubmit={onSubmit}
      onChange={onChange}
      id="role-assignments-filter"
      {...testIdProps('role-assignments-filter')}
      label={placeholderText}
      placeholder={placeholderText}
    />
  )
}
