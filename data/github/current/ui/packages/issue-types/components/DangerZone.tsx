import {type FC, useCallback, useRef, useState} from 'react'
import {Resources} from '../constants/strings'
import {Box, Button, Heading} from '@primer/react'

import {graphql, useFragment} from 'react-relay'
import type {DangerZoneIssueType$key} from './__generated__/DangerZoneIssueType.graphql'
import {DisableOrganizationConfirmationDialog} from './DisableOrganizationConfirmationDialog'

import {useIssueTypesAnalytics} from '../hooks/use-issue-types-analytics'
import {DeletionConfirmationDialog} from './DeletionConfirmationDialog'
import {useEnableDisableIssueType} from '../hooks/use-enable-disable-issue-type'

type DangerZoneProps = {
  issueType: DangerZoneIssueType$key
  owner: string
}

export const DangerZone: FC<DangerZoneProps> = ({issueType, owner}) => {
  const {sendIssueTypesAnalyticsEvent} = useIssueTypesAnalytics()
  const [isDisableDialogOpen, setIsDisableDialogOpen] = useState<boolean>(false)
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState<boolean>(false)
  const returnFocusRefDisable = useRef<HTMLButtonElement>(null)
  const returnFocusRefDeletion = useRef<HTMLButtonElement>(null)

  const {enableOrganizationIssueType} = useEnableDisableIssueType()

  const data = useFragment<DangerZoneIssueType$key>(
    graphql`
      fragment DangerZoneIssueType on IssueType {
        id
        isEnabled
        ...DisableOrganizationConfirmationDialogIssueType
        ...DeletionConfirmationDialogIssueType
      }
    `,
    issueType,
  )

  const enableIssueType = useCallback(() => {
    sendIssueTypesAnalyticsEvent('org_issue_type.enable', 'ORG_ISSUE_TYPE_ENABLE_BUTTON')
    enableOrganizationIssueType(data.id, () => setIsDisableDialogOpen(false))
  }, [data.id, sendIssueTypesAnalyticsEvent, enableOrganizationIssueType])

  return (
    <div>
      <Heading as="h3" sx={{fontSize: 3, mb: 3, fontWeight: 'normal'}}>
        Danger zone
      </Heading>
      <Box sx={{borderColor: 'danger.emphasis', borderWidth: '1px', borderStyle: 'solid', borderRadius: 2}}>
        <Box
          sx={{
            display: 'flex',
            flex: 1,
            justifyContent: 'space-between',
            alignItems: 'center',
            borderBottom: '1px solid',
            borderColor: 'border.muted',
            p: 3,
          }}
        >
          {/* title and description */}
          <Box sx={{display: 'flex', flexDirection: 'column'}}>
            <Heading as="h4" sx={{fontSize: 1, fontWeight: 'bold'}}>
              {data.isEnabled
                ? Resources.dangerZoneDisableIssueTypeHeading
                : Resources.dangerZoneEnableIssueTypeHeading}
            </Heading>
            <span>
              {data.isEnabled ? Resources.dangerZoneDisableIssueTypeInfo : Resources.dangerZoneEnableIssueTypeInfo}
            </span>
          </Box>
          <Button
            variant="danger"
            data-testid="danger-zone-enable"
            onClick={() => (data.isEnabled ? setIsDisableDialogOpen(true) : enableIssueType())}
            ref={returnFocusRefDisable}
          >
            {data.isEnabled ? Resources.disableButton : Resources.enableButton}
          </Button>
          {isDisableDialogOpen && (
            <DisableOrganizationConfirmationDialog
              closeDialog={() => setIsDisableDialogOpen(false)}
              issueType={data}
              returnFocusRefDisable={returnFocusRefDisable}
            />
          )}
        </Box>

        <Box sx={{display: 'flex', flex: 1, p: 3, justifyContent: 'space-between'}}>
          {/* title and description */}
          <Box sx={{display: 'flex', flexDirection: 'column'}}>
            <Heading as="h4" sx={{fontSize: 1, fontWeight: 'bold'}}>
              {Resources.dangerZoneDeleteIssueTypeHeading}
            </Heading>
            <span>{Resources.dangerZoneDeleteIssueTypeInfo}</span>
          </Box>
          <Button
            data-testid="danger-zone-delete"
            variant="danger"
            onClick={() => setIsDeleteDialogOpen(true)}
            ref={returnFocusRefDeletion}
          >
            {Resources.deleteButton}
          </Button>
          {isDeleteDialogOpen && (
            <DeletionConfirmationDialog
              closeDialog={() => setIsDeleteDialogOpen(false)}
              owner={owner}
              issueType={data}
              returnFocusRefDeletion={returnFocusRefDeletion}
            />
          )}
        </Box>
      </Box>
    </div>
  )
}
