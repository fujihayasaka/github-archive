import {ActionList, ActionMenu, Heading, Link, Spinner, Stack} from '@primer/react'
import {useId, useMemo} from 'react'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {
  disableModelsBillingPayload,
  enableModelsBillingPayload,
  useUpdateOrganizationBilling,
} from '../hooks/use-update-organization-billing'
import {AlertIcon, ShieldLockIcon} from '@primer/octicons-react'
import styles from './ModelsBilling.module.css'
import {modelsPricingLink} from '../constants'

export function ModelsBilling({
  billingEnabled,
  orgDisplayLogin,
  canEnableModelsBilling,
}: {
  billingEnabled: boolean
  orgDisplayLogin: string
  canEnableModelsBilling: boolean
}) {
  const isModelsBillingUIFeatureEnabled = useFeatureFlag('github_models_billing_ui')
  const billingDetailsPath = `/organizations/${orgDisplayLogin}/settings/billing/usage`
  const billingBudgetsPath = `/organizations/${orgDisplayLogin}/settings/billing/budgets`

  const {
    data: updatedModelsBillingValue,
    mutate: updateOrganizationModelsBilling,
    isPending: isUpdatePending,
    isError: didUpdateError,
  } = useUpdateOrganizationBilling({orgDisplayLogin})
  const errorMessageId = useId()

  const modelsBillingEnabled = useMemo(() => {
    return updatedModelsBillingValue?.enabled ?? billingEnabled
  }, [updatedModelsBillingValue?.enabled, billingEnabled])

  if (!isModelsBillingUIFeatureEnabled) return null

  return (
    <>
      <Heading as="h2" data-hpc variant="small" className="mt-4 mb-2">
        Billing
      </Heading>
      <Stack direction="vertical" gap="none">
        <div className={styles.container}>
          <Stack direction="horizontal" gap="condensed" justify="space-between">
            <Stack direction="vertical" gap="condensed" className="mr-4">
              <Heading as="h3" variant="small">
                Additional Models usage
              </Heading>
              <p className="fgColor-muted mb-0">
                If enabled, models usage will be billed per token based on model pricing from your Model&apos;s budget.
              </p>
              <span>
                <Link inline href={billingDetailsPath} className="mr-3">
                  View billing details
                </Link>
                <Link inline href={modelsPricingLink}>
                  Models pricing
                </Link>
              </span>
            </Stack>
            {canEnableModelsBilling ? (
              <Stack justify="center">
                <ActionMenu>
                  <ActionMenu.Button
                    disabled={isUpdatePending}
                    aria-describedby={didUpdateError ? errorMessageId : undefined}
                    leadingVisual={() => {
                      if (didUpdateError) return <AlertIcon />
                      if (isUpdatePending) return <Spinner size="small" />
                      return null
                    }}
                    className={didUpdateError ? 'mr-3' : undefined}
                  >
                    <span className="sr-only">Models billing status: </span>
                    <span>{modelsBillingEnabled ? 'Enabled' : 'Disabled'}</span>
                  </ActionMenu.Button>
                  <ActionMenu.Overlay>
                    {!isUpdatePending && (
                      <ActionList selectionVariant="single" variant="full" showDividers>
                        <ActionList.Item
                          selected={modelsBillingEnabled}
                          onSelect={() => updateOrganizationModelsBilling(enableModelsBillingPayload())}
                        >
                          Enabled
                          <ActionList.Description variant="block">
                            Organization will allow additional paid models usage.
                          </ActionList.Description>
                        </ActionList.Item>
                        <ActionList.Item
                          selected={!modelsBillingEnabled}
                          onSelect={() => updateOrganizationModelsBilling(disableModelsBillingPayload())}
                        >
                          Disabled
                          <ActionList.Description variant="block">
                            Organization will have free rate limits.
                          </ActionList.Description>
                        </ActionList.Item>
                      </ActionList>
                    )}
                  </ActionMenu.Overlay>
                </ActionMenu>
                {didUpdateError && (
                  <div id={errorMessageId} className="fgColor-danger">
                    There was a problem enabling/disabling billing for Models. Please try again later.
                  </div>
                )}
              </Stack>
            ) : (
              <Stack align="center" direction="horizontal" className="color-fg-muted">
                <ShieldLockIcon size="small" /> <span>Disabled</span>
              </Stack>
            )}
          </Stack>
        </div>
        <Stack>
          <div className={styles.footer}>
            <p className="fgColor-muted mb-0">
              {modelsBillingEnabled ? (
                <>
                  Paid usage has been enabled for Models.{' '}
                  <Link inline href={billingBudgetsPath}>
                    Set a budget
                  </Link>{' '}
                  to manage the Models spending.
                </>
              ) : (
                'You currently use free tier token limit. Turn on billing for additional usage to avoid interruptions.'
              )}
            </p>
          </div>
        </Stack>
      </Stack>
    </>
  )
}
