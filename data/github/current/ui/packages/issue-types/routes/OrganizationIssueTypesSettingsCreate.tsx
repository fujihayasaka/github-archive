import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {Box, Link, Text} from '@primer/react'
import {useCallback, useMemo, useState} from 'react'
import {Title} from '../components/Title'
import {Resources} from '../constants/strings'
import {commitCreateIssueTypeMutation} from '../mutations/create-issue-type-mutation'
import {isEnterprise} from '@github-ui/runtime-environment'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import type {ColorName} from '@github-ui/use-named-color'
import {type EntryPointComponent, graphql, useFragment, usePreloadedQuery, useRelayEnvironment} from 'react-relay'
import {useParams} from 'react-router-dom'
import {TypeColor} from '../components/TypeColor'
import {TypeDescription} from '../components/TypeDescription'
import {TypeName} from '../components/TypeName'
import {TypePrivate} from '../components/TypePrivate'
import {TypeSubmissionButtons} from '../components/TypeSubmissionButtons'
import {ORGANIZATION_ISSUE_TYPES_LIMIT} from '../constants/constants'
import {useInputFieldsErrors} from '../hooks/use-input-fields-errors'
import {useIssueTypesAnalytics} from '../hooks/use-issue-types-analytics'
import type {CreateIssueTypeInput} from '../mutations/__generated__/createIssueTypeMutation.graphql'
import {formatError} from '../utils'
import type {OrganizationIssueTypesSettingsCreateIssueTypes$key} from './__generated__/OrganizationIssueTypesSettingsCreateIssueTypes.graphql'
import type {OrganizationIssueTypesSettingsCreateQuery} from './__generated__/OrganizationIssueTypesSettingsCreateQuery.graphql'

export const organizationIssueTypesQuery = graphql`
  query OrganizationIssueTypesSettingsCreateQuery($organization_id: String!) {
    viewer {
      isEnterpriseManagedUser
    }
    organization(login: $organization_id) {
      id
      login
      issueTypes {
        ...OrganizationIssueTypesSettingsCreateIssueTypes
      }
    }
  }
`

export const OrganizationIssueTypesSettingsCreate: EntryPointComponent<
  {organizationIssueTypesSettingsCreateQuery: OrganizationIssueTypesSettingsCreateQuery},
  Record<string, never>
> = ({queries: {organizationIssueTypesSettingsCreateQuery}}) => {
  const preloadedData = usePreloadedQuery<OrganizationIssueTypesSettingsCreateQuery>(
    organizationIssueTypesQuery,
    organizationIssueTypesSettingsCreateQuery,
  )

  const {organization_id: owner} = useParams()
  const analyticsMetadata = useMemo(() => ({owner: owner ?? ''}), [owner])

  if (!preloadedData?.organization?.id) return null

  return (
    <AnalyticsProvider appName="issue_types" category="create" metadata={analyticsMetadata}>
      <OrganizationIssueTypesSettingsCreateInternal
        ownerId={preloadedData.organization.id}
        ownerName={preloadedData.organization.login}
        issueTypes={preloadedData.organization.issueTypes}
        isEnterpriseManagedUser={preloadedData?.viewer?.isEnterpriseManagedUser || false}
      />
    </AnalyticsProvider>
  )
}

type OrganizationIssueTypesSettingsCreateInternalProps = {
  ownerId: string
  ownerName: string
  issueTypes?: OrganizationIssueTypesSettingsCreateIssueTypes$key | null
  isEnterpriseManagedUser: boolean
}

const OrganizationIssueTypesSettingsCreateInternal = ({
  ownerId,
  ownerName,
  issueTypes,
  isEnterpriseManagedUser,
}: OrganizationIssueTypesSettingsCreateInternalProps) => {
  const data = useFragment<OrganizationIssueTypesSettingsCreateIssueTypes$key>(
    graphql`
      fragment OrganizationIssueTypesSettingsCreateIssueTypes on IssueTypeConnection {
        totalCount
        edges {
          node {
            name
          }
        }
      }
    `,
    issueTypes,
  )
  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const [name, setName] = useState<string>('')
  const [description, setDescription] = useState<string>('')
  const [color, setColor] = useState<ColorName>('GRAY')
  const [isPrivate, setIsPrivate] = useState<boolean>(false)
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false)

  const {sendIssueTypesAnalyticsEvent} = useIssueTypesAnalytics()

  const disablePrivateTypeCreation = isFeatureEnabled('issue_types_prevent_private_type_creation') || isEnterprise()

  const existingIssueTypeNames = useMemo(() => {
    return data?.edges?.map(e => e?.node?.name).filter(n => n !== undefined) ?? []
  }, [data])
  const {
    typeNameRef,
    typeDescriptionRef,
    nameError,
    setNameError,
    descriptionError,
    setDescriptionError,
    setShouldFocusError,
    validate,
  } = useInputFieldsErrors(existingIssueTypeNames)

  const handleCancel = () => {
    if (ssrSafeWindow) {
      ssrSafeWindow.location.href = `/organizations/${ownerName}/settings/issue-types`
    }
  }

  const handleCreate = useCallback(() => {
    const valid = validate()

    if (!valid) {
      setShouldFocusError(true)
      return
    }

    const mutationInput: CreateIssueTypeInput = {
      ownerId,
      name,
      description,
      color,
      isEnabled: true,
      isPrivate,
      // not providing issue type as it will be set to custom by default on the backend and the four default types get created by enabling them, not by going to the create page
    }

    if (disablePrivateTypeCreation) {
      delete mutationInput.isPrivate
    }

    sendIssueTypesAnalyticsEvent('org_issue_type.create', 'ORG_ISSUE_TYPE_CREATE_BUTTON')
    setIsSubmitting(true)
    commitCreateIssueTypeMutation({
      environment,
      input: mutationInput,
      onError: () => {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: Resources.creatingIssueTypeError,
        })
        setIsSubmitting(false)
      },
      onCompleted: response => {
        const errors = response.createIssueType?.errors || []
        if (errors.length === 0) {
          if (ssrSafeWindow) {
            ssrSafeWindow.location.href = `/organizations/${ownerName}/settings/issue-types`
            return
          }
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'success',
            message: Resources.creatingIssueTypeSuccess,
          })
        } else {
          errors.map((e: {message: string}) => {
            reportError(formatError('UpdateIssueType', e.message))
            if (e.message.startsWith('Name')) {
              setNameError(e.message)
            } else if (e.message.startsWith('Description')) {
              setDescriptionError(e.message)
            } else if (e.message.startsWith('Maximum')) {
              // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
              addToast({
                type: 'error',
                message: e.message,
              })
            }
          })
          setShouldFocusError(true)
        }
        setIsSubmitting(false)
      },
    })
  }, [
    validate,
    ownerId,
    name,
    description,
    color,
    isPrivate,
    disablePrivateTypeCreation,
    sendIssueTypesAnalyticsEvent,
    environment,
    setShouldFocusError,
    addToast,
    ownerName,
    setNameError,
    setDescriptionError,
  ])

  const showPrivateTypeOption = !isEnterpriseManagedUser && !disablePrivateTypeCreation

  return (
    <div>
      <Title page="create">
        <Link href={`/organizations/${ownerName}/settings/issue-types`}>{Resources.settingsPageHeader}</Link>
        {` / ${Resources.newTitle}`}
      </Title>
      <Box sx={{mb: 4}}>
        {/* Hide the form if the ORGANIZATION_ISSUE_TYPES_LIMIT is reached */}
        {data?.totalCount === ORGANIZATION_ISSUE_TYPES_LIMIT ? (
          <Box sx={{mt: 5, display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <Text sx={{fontWeight: 600}}>You have reached the maximum number of issue types</Text>
            <Text sx={{color: 'fg.subtle'}}>To create a new one, please remove an existing type.</Text>
          </Box>
        ) : (
          <>
            <TypeName
              disabled={isSubmitting}
              name={name}
              setName={setName}
              error={nameError}
              setError={setNameError}
              ref={typeNameRef}
            />
            <TypeDescription
              disabled={isSubmitting}
              description={description}
              setDescription={setDescription}
              error={descriptionError}
              setError={setDescriptionError}
              ref={typeDescriptionRef}
            />
            <TypeColor color={color} setColor={setColor} />
            {showPrivateTypeOption && (
              <TypePrivate disabled={isSubmitting} isPrivate={isPrivate} setIsPrivate={setIsPrivate} />
            )}
            <TypeSubmissionButtons
              disabled={isSubmitting}
              confirmLabel={Resources.saveCreatedIssueTypeButton}
              onCancel={handleCancel}
              onConfirm={handleCreate}
            />
          </>
        )}
      </Box>
    </div>
  )
}
