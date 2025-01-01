import {ControlGroup} from '@github-ui/control-group'
import {useRef, useState} from 'react'
import {IconButton, TextInput} from '@primer/react'
import {CheckIcon, XIcon} from '@primer/octicons-react'
import {updateResourceLink} from '../../../../utils/api-helpers'
import {useAppContext} from '../../../../contexts/AppContext'
import Validation from '../../../Validation'

import styles from './ResourceLinks.module.css'

export interface ResourceLinksProps {
  value: null | string
}

const ResourceLinks: React.FC<ResourceLinksProps> = ({value}) => {
  const {enterprise} = useAppContext()
  const enterpriseSlug = enterprise!.slug

  const [editMode, setEditMode] = useState(false)
  const [displayValue, setDisplayValue] = useState(value || '')
  const formRef = useRef<HTMLInputElement>(null)
  const [saveError, setSaveError] = useState<string | null>(null)

  const saveInput = async () => {
    const userInput = formRef.current!.value

    const resp = await updateResourceLink(enterpriseSlug, {input: userInput})

    if (resp && resp.success === true) {
      setDisplayValue(userInput)
      setSaveError(null)
      setEditMode(false)
    } else {
      if (resp && resp.error_message) {
        setSaveError(resp.error_message)
      } else {
        setSaveError('Something went wrong, please try again.')
      }
    }
  }

  const cancelEdit = () => {
    setEditMode(false)
    setSaveError(null)
  }

  // Buttons to display when in edit mode for saving / discarding changes:
  const saveButtons = (
    <ControlGroup.Custom>
      <IconButton
        icon={CheckIcon}
        aria-label="Save"
        variant="primary"
        onClick={saveInput}
        className={styles.IconButton}
      />
      <IconButton icon={XIcon} aria-label="Cancel" onClick={cancelEdit} />
    </ControlGroup.Custom>
  )

  // Form to display when in edit mode for user input:
  const editForm = (
    <>
      <TextInput
        block
        placeholder="Resource link"
        defaultValue={displayValue}
        ref={formRef}
        className={styles.TextInput}
      />
      {saveError && <Validation validationStatus="error">{saveError}</Validation>}
    </>
  )

  return (
    <ControlGroup.Item>
      <ControlGroup.Title id="resource-link">Resource link for push protection</ControlGroup.Title>
      <ControlGroup.Description>
        Add a resource link in the CLI and web UI when a commit is blocked. Link will be shown in addition to the
        message GitHub displays.
        {editMode && editForm}
      </ControlGroup.Description>
      {editMode ? (
        saveButtons
      ) : (
        <ControlGroup.InlineEdit
          data-testid="edit-resource-link"
          onClick={() => setEditMode(true)}
          value={displayValue}
        />
      )}
    </ControlGroup.Item>
  )
}

export default ResourceLinks
