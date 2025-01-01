import {useEffect, useState} from 'react'
import {Box, Dialog, IconButton, TextInput} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {SearchIcon, XIcon} from '@primer/octicons-react'
import {debounce} from '@github/mini-throttle'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {partition} from './utils'
import type {SimpleOrganization} from './types'
import styles from './OrgSelectionDialog.module.css'

export interface OrgSelectionDialogProps {
  action: string
  organizations: SimpleOrganization[]
  closeDialog: () => void
}

interface IActionsCustomImagesBulkOrgUpdate {
  enabledOrgIds: number[]
  disabledOrgIds: number[]
}

const sortOrgs = (left: SimpleOrganization, right: SimpleOrganization): number => {
  // Put selected orgs first, then sort alphabetically
  if (left.selected !== right.selected) {
    return left.selected ? -1 : 1
  }
  return left.name.localeCompare(right.name)
}

export function OrgSelectionDialog({action, organizations, closeDialog}: OrgSelectionDialogProps) {
  const [orgs, setOrgs] = useState<SimpleOrganization[]>(organizations.sort(sortOrgs))
  const [filter, setFilter] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [submitDisabled, setSubmitDisabled] = useState(true)
  const [submitError, setSubmitError] = useState(false)

  async function updateSelectedOrgs() {
    const updatedOrgs = orgs.filter(org => isOrgUpdated(org))
    if (updatedOrgs.length === 0) {
      // no-op
      return
    }

    // Split the updated orgs into selected and unselected
    const [selected, unselected] = partition(updatedOrgs, org => isOrgSelectedInView(org))
    const enabledOrgIds = selected.map(org => org.id)
    const disabledOrgIds = unselected.map(org => org.id)

    // Lock the UI
    setSubmitting(true)
    setSubmitError(false)

    // Call the backend to update the selected orgs
    const update: IActionsCustomImagesBulkOrgUpdate = {enabledOrgIds, disabledOrgIds}
    const response = await reactFetchJSON(action, {
      method: 'PUT',
      body: update,
    })
    if (response.ok) {
      window.location.reload()
    } else {
      setSubmitting(false)
      setSubmitError(true)
    }
  }

  function isOrgUpdated(org: SimpleOrganization) {
    return org.selectedUpdated !== undefined && org.selected !== org.selectedUpdated
  }

  function setOrgSelected(org: SimpleOrganization, isSelected: boolean) {
    setOrgs(orgs.map(o => (o.id === org.id ? {...o, selectedUpdated: isSelected} : o)))
  }

  function isOrgSelectedInView(org: SimpleOrganization): boolean {
    if (org.selectedUpdated !== undefined) {
      return org.selectedUpdated
    }
    return org.selected
  }

  const debounceOrgFilter = debounce((newFilter: string) => setFilter(newFilter), 400)

  useEffect(() => setSubmitDisabled(submitting || !orgs.some(isOrgUpdated)), [submitting, orgs, setSubmitDisabled])

  function renderHeader(dialogLabelId: string) {
    return (
      <Box
        className="color-bg-subtle color-border-default"
        sx={{
          padding: 3,
          display: 'flex',
          flexDirection: 'column',
          borderTopWidth: 0,
          borderLeftWidth: 0,
          borderRightWidth: 0,
          borderBottomWidth: 1,
          borderTopLeftRadius: 'var(--borderRadius-large)',
          borderTopRightRadius: 'var(--borderRadius-large)',
          borderStyle: 'solid',
        }}
      >
        <Box sx={{display: 'flex', alignItems: 'center'}}>
          <Dialog.Title id={dialogLabelId} className={styles.Dialog_Title}>
            Select organizations
          </Dialog.Title>
          <IconButton variant="invisible" aria-label="Close Dialog" icon={XIcon} onClick={closeDialog} />
        </Box>
        <TextInput
          sx={{width: '100%', fontWeight: 'normal', marginTop: 1}}
          block={false}
          leadingVisual={SearchIcon}
          placeholder="Search"
          onChange={e => debounceOrgFilter(e.target.value)}
          data-testid="org-filter-textinput"
        />
      </Box>
    )
  }

  return (
    <Dialog
      onClose={closeDialog}
      height="large"
      width="medium"
      renderHeader={({dialogLabelId}) => renderHeader(dialogLabelId)}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: closeDialog,
          disabled: submitting,
        },
        {
          buttonType: 'primary',
          content: 'Apply',
          onClick: updateSelectedOrgs,
          disabled: submitDisabled,
        },
      ]}
    >
      {submitError && (
        <Banner variant="critical" hideTitle title="Hosted Runners Custom Images">
          Failed to update the selected organizations, please try again later.
        </Banner>
      )}
      <ListView
        title="Select organizations"
        variant="compact"
        isSelectable
        singularUnits="organization"
        pluralUnits="organizations"
        data-testid="select-orgs-list"
      >
        {orgs
          .filter(org => org.name.includes(filter))
          .map(org => (
            <ListItem
              className={styles.listItem}
              isSelected={isOrgSelectedInView(org)}
              onSelect={isSelected => setOrgSelected(org, isSelected)}
              key={org.id}
              title={<ListItemTitle value={org.name} />}
            >
              {org.primaryAvatarUrl && (
                <ListItemLeadingContent style={{alignSelf: 'center'}}>
                  <GitHubAvatar alt={org.name} src={org.primaryAvatarUrl} />
                </ListItemLeadingContent>
              )}
            </ListItem>
          ))}
      </ListView>
    </Dialog>
  )
}
