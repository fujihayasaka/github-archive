import type {RepoPolicyInfo} from '@github-ui/code-view-types'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import {reactFetch} from '@github-ui/verified-fetch'
import {Link, Spinner} from '@primer/react'
import {Suspense, type ReactNode} from 'react'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useSuspenseQuery} from '@github-ui/react-query'

export function buildCodespacesPath(repoId: number, refName: string) {
  const encodeRef = encodeURIComponent(refName)
  return `/codespaces?codespace%5Bref%5D=${encodeRef}&current_branch=${encodeRef}&event_target=REPO_PAGE&repo=${repoId}`
}

function defaultErrorMessage(contactPath: string) {
  return (
    <span>
      An unexpected error occurred. Please{' '}
      <Link inline href={contactPath}>
        contact support
      </Link>{' '}
      for more information.
    </span>
  )
}

export interface CodespacesTabProps {
  hasAccessToCodespaces: boolean
  repositoryPolicyInfo?: RepoPolicyInfo
  contactPath: string
  currentUserIsEnterpriseManaged?: boolean
  enterpriseManagedBusinessName?: string
  newCodespacePath?: string
  codespacesPath: string
  isLoggedIn: boolean
}

function ErrorMessage({header, message}: {header: string; message: ReactNode}) {
  return (
    <div className="blankslate">
      <p className="fgColor-default text-bold mb-1">{header}</p>
      <p className="mt-2 mx-4">{message}</p>
    </div>
  )
}

export function CodespacesTabWrapper({children}: {children?: ReactNode}) {
  return (
    <div className="d-flex flex-justify-center">
      <ErrorBoundary
        fallback={<ErrorMessage header="Codespaces data failed to load." message="Refresh the page and try again." />}
      >
        <Suspense
          fallback={
            <div className="m-2">
              <Spinner />
            </div>
          }
        >
          {children}
        </Suspense>
      </ErrorBoundary>
    </div>
  )
}

export function ServerRenderedCodespacesTabContent({codespacesPath}: {codespacesPath: string}) {
  const {data: content} = useSuspenseQuery({
    queryKey: ['CodespacesTabContent.content', codespacesPath],
    queryFn: async () => {
      const result = await reactFetch(codespacesPath)
      if (result.status >= 400 && result.status <= 499) {
        return ''
      } else if (!result.ok) {
        throw new Error(`HTTP ${result.status}`)
      }
      return await result.text()
    },
  })

  return <SafeHTMLBox className="width-full" html={content as SafeHTMLString} />
}

export function CodespacesTabContent(props: CodespacesTabProps) {
  const {
    hasAccessToCodespaces,
    repositoryPolicyInfo,
    contactPath,
    currentUserIsEnterpriseManaged,
    enterpriseManagedBusinessName,
    newCodespacePath,
    codespacesPath,
    isLoggedIn,
  } = props

  if (!hasAccessToCodespaces) {
    if (!isLoggedIn) {
      return (
        <ErrorMessage
          header="Sign in required"
          message={
            <span>
              Please{' '}
              <Link inline href={newCodespacePath}>
                sign in
              </Link>{' '}
              to use Codespaces.
            </span>
          }
        />
      )
    }

    if (!repositoryPolicyInfo?.allowed) {
      let message = null
      if (!repositoryPolicyInfo?.canBill && currentUserIsEnterpriseManaged) {
        message = (
          <span>
            <Link href="https://docs.github.com/enterprise-cloud@latest/admin/identity-and-access-management/using-enterprise-managed-users-for-iam/about-enterprise-managed-users">
              Enterprise-managed users
            </Link>
            {` must have their Codespaces usage paid for by ${enterpriseManagedBusinessName || 'their enterprise'}.`}
          </span>
        )
      } else if (repositoryPolicyInfo?.hasIpAllowLists) {
        message = (
          <span>
            Your organization or enterprise enforces{' '}
            <Link
              inline
              href="https://docs.github.com/enterprise-cloud@latest/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization"
            >
              IP allow lists
            </Link>
            which are unsupported by Codespaces at this time.
          </span>
        )
      } else if (repositoryPolicyInfo?.disabledByBusiness) {
        message = (
          <span>
            Your enterprise has disabled Codespaces at this time. Please contact your enterprise administrator for more
            information.
          </span>
        )
      } else if (repositoryPolicyInfo?.disabledByOrganization) {
        message = (
          <span>
            Your organization has disabled Codespaces on this repository. Please contact your organization administrator
            for more information.
          </span>
        )
      } else {
        message = defaultErrorMessage(contactPath)
      }
      return <ErrorMessage header="Codespace access limited" message={message} />
    } else if (!repositoryPolicyInfo?.changesWouldBeSafe) {
      return (
        <ErrorMessage
          header="Repository access limited"
          message={<span>You do not have access to push to this repository and its owner has disabled forking.</span>}
        />
      )
    } else {
      return <ErrorMessage header="Codespace access limited" message={defaultErrorMessage(contactPath)} />
    }
  }

  return <ServerRenderedCodespacesTabContent codespacesPath={codespacesPath} />
}

export function CodespacesTab(props: CodespacesTabProps) {
  return (
    <CodespacesTabWrapper>
      <CodespacesTabContent {...props} />
    </CodespacesTabWrapper>
  )
}
