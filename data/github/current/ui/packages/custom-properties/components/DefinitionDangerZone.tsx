import type {PropertyDefinition, PropertyNameOrgConflicts, SourceInfo} from '@github-ui/custom-properties-types'
import {Button, Heading} from '@primer/react'
import {type ReactNode, useRef, useState} from 'react'

import {DeleteDefinitionDialog} from './DeleteDefinitionDialog'
import {OrgConflictsDialog} from './OrgConflictsDialog'
import {PromoteDefinitionDialog} from './PromoteDefinitionDialog'

interface Props {
  definition: PropertyDefinition
  business?: SourceInfo
  orgConflicts?: PropertyNameOrgConflicts
  canDelete: boolean
  canPromote: boolean
}
export function DefinitionDangerZone({definition, business, canDelete, canPromote, orgConflicts}: Props) {
  const deleteButtonRef = useRef<HTMLButtonElement>(null)
  const promoteButtonRef = useRef<HTMLButtonElement>(null)

  const [deleteDialogIsOpen, setDeleteDialogIsOpen] = useState(false)
  const [promoteDialogIsOpen, setPromoteDialogIsOpen] = useState(false)
  const [conflictDialogIsOpen, setConflictDialogIsOpen] = useState(false)

  const openPromotionDialog = () => {
    if (orgConflicts?.usages.length) {
      setConflictDialogIsOpen(true)
    } else {
      setPromoteDialogIsOpen(true)
    }
  }

  const promoActionDescription =
    business &&
    definition.source &&
    `This property is managed by ${definition.source.name}. Promote this property to make ${business.name} the owner.`

  return (
    <div>
      <Heading as="h2" className="f3 mb-2">
        Additional options
      </Heading>
      <div className="border rounded-2">
        {canDelete && (
          <Row
            title="Delete property"
            subtitle="Permanently delete this property and its values from all repositories."
            action={
              <Button variant="danger" ref={deleteButtonRef} onClick={() => setDeleteDialogIsOpen(true)}>
                Delete property
              </Button>
            }
          />
        )}

        {canDelete && canPromote && <hr className="mx-3 my-0" />}

        {canPromote && (
          <Row
            title="Promote to enterprise"
            subtitle={promoActionDescription}
            action={
              <Button ref={promoteButtonRef} onClick={openPromotionDialog}>
                Promote to enterprise
              </Button>
            }
          />
        )}
      </div>

      {definition && deleteDialogIsOpen && (
        <DeleteDefinitionDialog
          returnFocusRef={deleteButtonRef}
          definition={definition}
          onCancel={() => setDeleteDialogIsOpen(false)}
          onDismiss={() => setDeleteDialogIsOpen(false)}
        />
      )}

      {definition && definition.source && business && promoteDialogIsOpen && (
        <PromoteDefinitionDialog
          business={business}
          returnFocusRef={promoteButtonRef}
          definition={{...definition, source: definition.source}}
          onCancel={() => setPromoteDialogIsOpen(false)}
          onDismiss={() => setPromoteDialogIsOpen(false)}
        />
      )}

      {orgConflicts && conflictDialogIsOpen && business && (
        <OrgConflictsDialog
          returnFocusRef={promoteButtonRef}
          title="Cannot promote to enterprise"
          displayMessage={`This property cannot be promoted to ${business.name} because there are conflicting properties`}
          orgConflicts={orgConflicts}
          onClose={() => setConflictDialogIsOpen(false)}
        />
      )}
    </div>
  )
}

interface RowProps {
  title: string
  subtitle?: string
  action: ReactNode
}
function Row({title, subtitle, action}: RowProps) {
  return (
    <div className="d-flex p-3">
      <div className="flex-1">
        <Heading as="h3" className="f5">
          {title}
        </Heading>
        <span className="color-fg-muted text-small">{subtitle}</span>
      </div>
      {action}
    </div>
  )
}
