import {SearchIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import {testIdProps} from '@github-ui/test-id-props'

export function RoleAssignmentsNoResultsBlankslate() {
  return (
    <div {...testIdProps('role-assignments-no-results-blankstate')}>
      <Blankslate spacious>
        <Blankslate.Visual>
          <SearchIcon size={24} />
        </Blankslate.Visual>
        <Blankslate.Heading>We couldn&apos;t find any assignments</Blankslate.Heading>
        <Blankslate.Description>
          No assignments match your search criteria. Adjust your search or clear the filter to see all role assignments.
        </Blankslate.Description>
      </Blankslate>
    </div>
  )
}
