import {Heading} from '@primer/react'
import {ModelsAccessToggle} from '../components/ModelsAccessToggle'
import {AccessPolicyProvider} from '../contexts/AccessPolicyContext'

export function AccessPolicyShow() {
  return (
    <AccessPolicyProvider>
      <div className="Subhead">
        <Heading as="h2" data-hpc variant="medium" className="Subhead-heading Subhead-heading--large">
          Models
        </Heading>
      </div>
      <ModelsAccessToggle />
    </AccessPolicyProvider>
  )
}
