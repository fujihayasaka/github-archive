/* eslint eslint-comments/no-use: off */
/* eslint-disable @github-ui/github-monorepo/filename-convention */
import {type FC, type FormEvent, type PropsWithChildren, type ReactElement, lazy, Suspense, useState} from 'react'
import {InfoIcon} from '@primer/octicons-react'
import {Button, FormControl, Textarea, Link, RelativeTime} from '@primer/react'
import {createExemptionRequest} from '../../services/api'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useParams} from 'react-router-dom'
import {useNavigate} from '@github-ui/use-navigate'
import {RoundedBox} from '../RoundedBox'
import {useDelegatedBypassSetBanner} from '../../contexts/DelegatedBypassBannerContext'
import type {
  RequestType,
  NewExemptionRequestPayload,
  ExemptionRequestPayload,
  SourceType,
} from '../../delegated-bypass-types'
import {useRequestFormContext} from '../../contexts/RequestFormContext'
import {SecretScanningSecretsDetails} from '../SecretScanningSecretsDetails'

import type {RuleRun} from '@github-ui/repos-rules/types/rules-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import SecretScanningReviewersDialog from './SecretScanningReviewersDialog'
import {SecretScanningAlertClosureDetails} from '../SecretScanningAlertClosureDetails'

const ApproversListDialog = lazy(() => import('../ApproversListDialog'))
const SecretScanningRequestForm = lazy(() => import('./SecretScanningRequestForm'))

type RegisteredComponent = {
  displayName: string
  FormControls?: FC
  instructions: {
    title: string
    Description: () => JSX.Element
    Content?: () => JSX.Element
    ApproversFooter: () => JSX.Element
  }
  violations?: FC<{ruleRuns: RuleRun[]}>
  ReviewerWarning?: FC
  bypassRequestListHeader: string
  bypassRequestListSubheaderFn: FC<{sourceType: string}>
  requestersUrlFn?: (scope: SourceType) => string
  approversUrlFn?: (scope: SourceType) => string
}

type ComponentRegistryProps = {
  requestType: RequestType
  hasPostApprovalAction?: boolean
}

export const componentRegistry: (props: ComponentRegistryProps) => RegisteredComponent = ({
  requestType,
  hasPostApprovalAction = false,
}) => {
  const registry: Record<RequestType, RegisteredComponent> = {
    multiple_bypass_types: {
      // Values of displayName and instructions are not used, since this type only appears on the list page. Still, provide some
      // generic strings in case they end up being rendered acccidentally.
      displayName: 'Delegated bypass requests',
      instructions: {
        title: 'Resolve rule violations',
        Description: () => <>Submit a request to bypass these protections.</>,
        Content: () => <>Resolve rule violations.</>,
        ApproversFooter: () => <span className="ml-1"> Requests are sent to all approvers.</span>,
      },
      bypassRequestListHeader: 'Bypass Requests',
      bypassRequestListSubheaderFn: () =>
        'Users may submit bypass requests to perform actions with rule violations. Actors on the bypass list of a ruleset may approve and manage bypass requests from this page.',
    },

    push_ruleset_bypass: {
      displayName: 'Push was blocked by push rules',
      instructions: {
        title: 'Resolve push protection violations',
        Description: () => {
          const {helpUrl} = useRoutePayload<NewExemptionRequestPayload>()

          return (
            <span>
              Submit a request to bypass these push protections. If granted, you may attempt this push again.{' '}
              <Link href={helpUrl} inline>
                Learn more
              </Link>
            </span>
          )
        },
        Content: () => <>Resolve push protection violations by removing the referenced commits from this push.</>,
        ApproversFooter: () => <span className="ml-1"> Requests are sent to all approvers.</span>,
      },
      bypassRequestListHeader: 'Bypass Requests',
      bypassRequestListSubheaderFn: () =>
        'Contributors may submit bypass requests to push commits with rule violations. Repository administrators and actors on the bypass list of a ruleset may approve and manage bypass requests from this page.',
    },

    repository_policy_ruleset_bypass: {
      displayName: 'Operation was blocked by repository policies',
      instructions: {
        title: 'Resolve repository policy violations',
        Description: () => (
          <span>
            Submit a request to bypass these repository policies. If granted,
            {hasPostApprovalAction ? ' it will be executed upon approval' : ' you may attempt this operation again'}.
          </span>
        ),
        ApproversFooter: () => <span className="ml-1"> Requests are sent to all approvers.</span>,
      },
      violations: () => null,
      ReviewerWarning: () => {
        const {
          enterprise,
          actionsEnabled,
          ruleSuite: {repository, operation},
        } = useRoutePayload<ExemptionRequestPayload>()
        let operationText = 'bypass policies for'
        switch (operation) {
          case 'delete':
            operationText = 'delete'
            break
          case 'change_visibility':
            operationText = 'change the visibility of'
            break
        }

        return (
          <>
            <span className="f4 text-bold mb-1">
              Approve request to {operationText} {repository.name}
            </span>
            {operation === 'delete' && (
              <span>
                This will permanently {operationText} the <strong>{repository.nameWithOwner}</strong> repository, wiki,
                issues, comments, {!enterprise ? 'packages, ' : ''} {actionsEnabled ? 'secrets, workflow runs, ' : ''}{' '}
                and remove all {repository.isOrgOwned ? 'team ' : 'collaborator '} associations.
              </span>
            )}
          </>
        )
      },
      bypassRequestListHeader: 'Bypass Requests',
      bypassRequestListSubheaderFn: () => 'View all requests to bypass repository policies.',
    },

    secret_scanning: {
      displayName: 'Push was blocked by secret scanning',
      FormControls: () => (
        <Suspense>
          <SecretScanningRequestForm />
        </Suspense>
      ),

      instructions: {
        title: 'Remove detected secrets',
        Description: () => (
          <span>Submit a request to bypass these push protections. If granted, you may attempt this push again.</span>
        ),
        Content: () => {
          const {owner} = useParams()
          const {helpUrl, orgGuidanceUrl} = useRoutePayload<NewExemptionRequestPayload>()

          if (orgGuidanceUrl) {
            return (
              <>
                <Link href={orgGuidanceUrl} inline>
                  Review guidance
                </Link>{' '}
                from <span className="text-bold">{owner}</span> and{' '}
                <Link href={helpUrl} inline>
                  remove any detected secrets
                </Link>{' '}
                from your commit and commit history.
              </>
            )
          }
          return (
            <>
              <Link href={helpUrl} inline>
                Remove any detected secrets
              </Link>{' '}
              from your commit and commit history.
            </>
          )
        },
        ApproversFooter: () => {
          const {approvers} = useRoutePayload<NewExemptionRequestPayload>()
          return <SecretScanningReviewersDialog approvers={approvers || [[], []]} />
        },
      },
      violations: ({ruleRuns}: {ruleRuns: RuleRun[]}) => (
        <Suspense>
          <SecretScanningSecretsDetails ruleRuns={ruleRuns} />
        </Suspense>
      ),
      bypassRequestListHeader: 'Push protection bypass requests',
      bypassRequestListSubheaderFn: ({sourceType}: {sourceType: string}) =>
        `View all requests to bypass push protection for secret scanning across your ${sourceType}.`,
      approversUrlFn: (scope: SourceType) => {
        if (scope === 'repository') {
          return 'bypass_requests/approvers'
        }
        return 'secret-scanning/approvers'
      },
      requestersUrlFn: (scope: SourceType) => {
        if (scope === 'repository') {
          return 'bypass_requests/requesters'
        }
        return 'secret-scanning/requesters'
      },
    },

    secret_scanning_closure: {
      displayName: 'Request to dismiss security alert',
      FormControls: () => (
        <Suspense>
          <SecretScanningRequestForm />
        </Suspense>
      ),
      instructions: {
        title: 'Request to dismiss security alert',
        Description: () => {
          return <></>
        }, // We're not using this at the moment, since we're submitting via the secret scanning alert page
        Content: () => {
          return <></>
        },
        ApproversFooter: () => {
          return <></>
        },
      },
      violations: () => <SecretScanningAlertClosureDetails />,
      approversUrlFn: (_scope: SourceType) => 'secret-scanning/approvers',
      requestersUrlFn: (_scope: SourceType) => 'secret-scanning/requesters',
      bypassRequestListHeader: 'Secret scanning alert dismissal requests',
      bypassRequestListSubheaderFn: ({sourceType}: {sourceType: string}) =>
        `View all requests to dismiss alerts for secret scanning across your ${sourceType}.`,
    },

    code_scanning_alert_dismissal: {
      displayName: 'Request to dismiss code scanning alert',
      FormControls: () => (
        <Suspense>
          <SecretScanningRequestForm />
        </Suspense>
      ),
      instructions: {
        title: 'Request to dismiss code scanning alert',
        Description: () => {
          return <></>
        }, // We're not using this at the moment, since we're submitting via the code scanning alert page
        Content: () => {
          return <></>
        },
        ApproversFooter: () => {
          return <></>
        },
      },
      violations: () => <SecretScanningAlertClosureDetails />,
      approversUrlFn: (_scope: SourceType) => 'code-scanning/approvers',
      requestersUrlFn: (_scope: SourceType) => 'code-scanning/requesters',
      bypassRequestListHeader: 'Code scanning alert dismissal requests',
      bypassRequestListSubheaderFn: ({sourceType}: {sourceType: string}) =>
        `View all requests to close alerts for code scanning across your ${sourceType}.`,
    },
  }
  return registry[requestType]
}

const SuccessBanner = ({rulesetId, expiresAt}: {rulesetId?: number; expiresAt?: string}) => {
  const [isApproversListOpen, setIsApproversListOpen] = useState(false)

  return (
    <>
      <>
        An email notification has been sent to all{' '}
        {rulesetId ? (
          <Link as="button" onClick={() => setIsApproversListOpen(true)}>
            approvers.
          </Link>
        ) : (
          <>approvers.</>
        )}{' '}
        Once this request is approved, you may attempt to push these commits again.{' '}
        {expiresAt && (
          <>
            This request will expire <RelativeTime datetime={new Date(expiresAt).toISOString()} />.
          </>
        )}
      </>
      {isApproversListOpen && rulesetId ? (
        <Suspense>
          <ApproversListDialog onClose={() => setIsApproversListOpen(false)} rulesetId={rulesetId} />
        </Suspense>
      ) : null}
    </>
  )
}

export const RequestForm = ({
  instructions,
  rulesetId,
  children,
}: PropsWithChildren<{
  instructions: RegisteredComponent['instructions']
  rulesetId?: number
}>) => {
  const [message, setMessage] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [commentError, setCommentError] = useState('')
  const navigate = useNavigate()
  const {owner, repo} = useParams()
  const setBanner = useDelegatedBypassSetBanner()
  const {formValues} = useRequestFormContext()
  const {Description, Content, ApproversFooter} = instructions

  const hasContent = !!Content
  const requestBypassText = `${hasContent ? 'or r' : 'R'}equest bypass privileges`

  function validateComment(comment: string) {
    if (comment.trim() === '') {
      setCommentError('A comment is required')
      return true
    } else {
      setCommentError('')
      return false
    }
  }

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    setSubmitting(true)
    e.preventDefault()
    if (validateComment(message)) {
      setSubmitting(false)
      return
    }
    const response = await createExemptionRequest(ssrSafeLocation.pathname, {...formValues, message: message.trim()})
    if (response.statusCode === 201) {
      setBanner({
        message: 'Your bypass request was submitted',
        variant: 'success',
        description: <SuccessBanner rulesetId={rulesetId} expiresAt={response.expires_at} />,
        announce: `Your bypass request was submitted. An email notification has been sent to all approvers. Once this request is approved, you may attempt to push these commits again. ${
          response.expires_at && `This request will expire ${new Date(response.expires_at).toLocaleString()}.`
        }`,
      })
      navigate(response.redirect_uri || `/${owner}/${repo}/exemptions/${response.request_number}`)
    } else if (response.statusCode === 422 && response.error) {
      setBanner({
        message: response.error,
        variant: 'danger',
      })
    } else {
      setBanner({
        message: 'There was a problem submitting your bypass request',
        variant: 'danger',
      })
    }
    setSubmitting(false)
  }

  return (
    <RoundedBox className="mt-4">
      {hasContent ? (
        <div className="p-4 d-flex flex-column">
          <span className="f4 text-bold mb-1">{instructions.title}</span>
          <span>
            <Content />
          </span>
        </div>
      ) : null}
      <form
        className="p-4 d-flex flex-column gap-4"
        method="post"
        action={ssrSafeLocation.pathname}
        noValidate
        onSubmit={onSubmit}
      >
        <div className="d-flex flex-column">
          <span className="f4 text-bold mb-1">{requestBypassText}</span>
          <Description />
        </div>
        {children}
        <FormControl>
          <FormControl.Label required>Add a comment</FormControl.Label>
          <Textarea
            block
            rows={5}
            placeholder="Type your comment here..."
            value={message}
            onChange={e => {
              setMessage(e.target.value)
              setCommentError('')
              validateComment(e.target.value)
            }}
            onBlur={e => validateComment(e.target.value)}
          />
          {commentError && <FormControl.Validation variant="error">{commentError}</FormControl.Validation>}
        </FormControl>
        <Button block type="submit" size="large" disabled={submitting}>
          Submit request
        </Button>
        <div className="note">
          <InfoIcon size={16} />
          <ApproversFooter />
        </div>
      </form>
    </RoundedBox>
  )
}
