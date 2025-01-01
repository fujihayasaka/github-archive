/* eslint eslint-comments/no-use: off */
/* eslint-disable filenames/match-regex */
import {type FC, type FormEvent, type PropsWithChildren, lazy, Suspense, useState} from 'react'
import {InfoIcon} from '@primer/octicons-react'
import {Box, Button, FormControl, Text, Textarea, Link} from '@primer/react'
import {createExemptionRequest} from '../../services/api'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useParams} from 'react-router-dom'
import {useNavigate} from '@github-ui/use-navigate'
import {RoundedBox} from '../RoundedBox'
import {useDelegatedBypassSetBanner} from '../../contexts/DelegatedBypassBannerContext'
import type {RequestType, NewExemptionRequestPayload} from '../../delegated-bypass-types'
import {useRequestFormContext} from '../../contexts/RequestFormContext'
import {SecretScanningSecretsDetails} from '../SecretScanningSecretsDetails'

import type {RuleRun} from '@github-ui/repos-rules/types/rules-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import SecretScanningReviewersDialog from './SecretScanningReviewersDialog'
import {SecretScanningAlertClosureDetails} from '../SecretScanningAlertClosureDetails'

const SecretScanningRequestForm = lazy(() => import('./SecretScanningRequestForm'))

type RegisteredComponent = {
  displayName: string
  FormControls?: FC
  instructions: {
    title: string
    description: string
    Content?: () => JSX.Element
    ApproversFooter: () => JSX.Element
  }
  violations?: FC<{ruleRuns: RuleRun[]}>
  orgApproversUrl?: string
  orgRequestersUrl?: string
  bypassRequestListHeader: string
  bypassRequestListSubheader: string
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
    push_ruleset_bypass: {
      displayName: 'Push was blocked by push rules',
      instructions: {
        title: 'Resolve push protection violations',
        description: 'Submit a request to bypass these push protections. If granted, you may attempt this push again.',
        Content: () => <>Resolve push protection violations by removing the referenced commits from this push.</>,
        ApproversFooter: () => <Text sx={{ml: 1}}> Requests are sent to all approvers.</Text>,
      },
      bypassRequestListHeader: 'Bypass Requests',
      bypassRequestListSubheader: 'View all requests to bypass push rules.',
    },
    repository_policy_ruleset_bypass: {
      displayName: 'Operation was blocked by repository policies',
      instructions: {
        title: 'Resolve repository policy violations',
        description: `Submit a request to bypass these repository policies. If granted, ${
          hasPostApprovalAction ? 'it will be executed upon approval' : 'you may attempt this operation again'
        }.`,
        ApproversFooter: () => <Text sx={{ml: 1}}> Requests are sent to all approvers.</Text>,
      },
      bypassRequestListHeader: 'Bypass Requests',
      bypassRequestListSubheader: 'View all requests to bypass repository.',
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
        description: 'Submit a request to bypass these push protections. If granted, you may attempt this push again.',
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
      orgApproversUrl: 'bypass_requests/approvers',
      orgRequestersUrl: 'bypass_requests/requesters',
      bypassRequestListHeader: 'Push protection bypass requests',
      bypassRequestListSubheader:
        'View all requests to bypass push protection for secret scanning across your organization.',
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
        description: '', // We're not using this at the moment, since we're submitting via the secret scanning alert page
        Content: () => {
          return <></>
        },
        ApproversFooter: () => {
          return <></>
        },
      },
      violations: () => <SecretScanningAlertClosureDetails />,
      orgApproversUrl: '', // Not yet implemented
      orgRequestersUrl: '', // Not yet implemented
      bypassRequestListHeader: 'Secret scanning alert closure requests',
      bypassRequestListSubheader: 'View all requests to close alerts for secret scanning across your organization.',
    },
  }
  return registry[requestType]
}

export const RequestForm = ({
  instructions,
  children,
}: PropsWithChildren<{
  instructions: RegisteredComponent['instructions']
}>) => {
  const [message, setMessage] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [commentError, setCommentError] = useState('')
  const navigate = useNavigate()
  const {owner, repo} = useParams()
  const setBanner = useDelegatedBypassSetBanner()
  const {formValues} = useRequestFormContext()
  const {Content, ApproversFooter} = instructions

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
    <RoundedBox sx={{mt: 4}}>
      {hasContent ? (
        <Box
          sx={{
            p: 4,
            display: 'flex',
            flexDirection: 'column',
          }}
        >
          <Text sx={{fontSize: 2, fontWeight: 'bold', mb: 1}}>{instructions.title}</Text>
          <span>
            <Content />
          </span>
        </Box>
      ) : null}
      <Box
        as="form"
        sx={{p: 4, display: 'flex', flexDirection: 'column', gap: 4}}
        method="post"
        action={ssrSafeLocation.pathname}
        noValidate
        onSubmit={onSubmit}
      >
        <Box sx={{display: 'flex', flexDirection: 'column'}}>
          <Text sx={{fontSize: 2, fontWeight: 'bold', mb: 1}}>{requestBypassText}</Text>
          <span>{instructions.description}</span>
        </Box>
        {children}
        <FormControl>
          <FormControl.Label required>Add a comment</FormControl.Label>
          <Textarea
            block
            sx={{height: 132}}
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
        <Button block type="submit" sx={{height: 40}} disabled={submitting}>
          Submit request
        </Button>
        <div className="note">
          <InfoIcon size={16} />
          <ApproversFooter />
        </div>
      </Box>
    </RoundedBox>
  )
}
