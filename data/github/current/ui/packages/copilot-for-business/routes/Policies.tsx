import {clsx} from 'clsx'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {ShieldLockIcon} from '@primer/octicons-react'
import {Box, Link, Text, FormControl, Checkbox} from '@primer/react'
import {useCallback} from 'react'
import {ActionMenuButton} from '../traditional/components/ActionMenuButton'
import {BoxSection, PageHeading, SectionHeading, SubtleHeading} from '../traditional/components/Ui'
import type {CopilotForBusinessPoliciesPayload} from '../types'
import styles from './Policies.module.css'
import {seatManagementEndpoint} from '../traditional/helpers/api-endpoints'
import {useCreateMutator} from '../hooks/use-fetchers'
import GeneralPolicy from '../components/GeneralPolicy'
import PreviewFeatureHeading from '../components/PreviewFeatureHeading'
import {useUIAspectFromRoute} from '../hooks/use-ui-aspect-from-route'
import {useOptions} from '../hooks/use-options'
import {useEnsureOrgName} from '../hooks/use-ensure-org-name'

function FeaturesForDataRetention({copilot_for_dotcom_visible}: {copilot_for_dotcom_visible: boolean | null}) {
  const features = []
  features.push('Copilot in the CLI')
  if (copilot_for_dotcom_visible) features.push('Copilot in GitHub.com')
  features.push('Copilot Chat in GitHub Mobile')
  let message = ''
  if (features.length === 1) {
    message = `Enabling ${features[0]} will collect additional data and updated`
  } else if (features.length === 2) {
    message = `Enabling ${features[0]} and ${features[1]} will collect additional data and updated`
  } else if (features.length === 3) {
    message = `Enabling ${features[0]}, ${features[1]} and ${features[2]} will collect additional data and updated`
  }

  return (
    <>
      {message && (
        <>
          {message}{' '}
          <Link
            href="https://github.com/customer-terms/github-copilot-product-specific-terms"
            className="Link--inTextBlock"
            inline
          >
            Product Terms
          </Link>{' '}
          apply.{' '}
        </>
      )}
    </>
  )
}

export default function PoliciesPage() {
  const copilot_for_dotcom_visible = useUIAspectFromRoute('copilot_for_dotcom').visible
  const copilot_bing_visible = useUIAspectFromRoute('bing_github_chat').visible
  const showEditorPreviewFeatures = useUIAspectFromRoute('editor_preview_features').visible
  const show_copilot_extensions_policy = useFeatureFlag('copilot_extension_access')
  const show_copilot_telemetry_policy = useFeatureFlag('copilot_private_telemetry_access')
  const showCopilotDesktopPolicy = useFeatureFlag('copilot_desktop')
  const showOveragesPolicy = useFeatureFlag('copilot_overages')
  const showSweAgentPolicy = useUIAspectFromRoute('swe_agent').visible
  const showMcpPolicy = useUIAspectFromRoute('mcp').visible
  const showSparkPolicy = useFeatureFlag('copilot_workbench')

  const payload = useRoutePayload<CopilotForBusinessPoliciesPayload>()
  const {enterprise_name, enterprise_slug, copilot_plan: plan, docsUrls} = payload

  return (
    <>
      <PageHeading name="GitHub Copilot" />
      <div className={clsx(styles.topBox, 'mb-3')}>
        <span className={clsx(styles.muted, 'mb-3')}>
          You can manage policies and grant access to Copilot features for all members with access.
          <br />
          Note that users from other organizations may gain access if permitted by their administrators.
        </span>
        {enterprise_name && enterprise_slug && (
          <span className={clsx(styles.muted, 'mr-2', 'mb-3')} data-testid="cfb-managed-organization-enterprise">
            <ShieldLockIcon /> Managed by{' '}
            <Link inline href={`/enterprises/${enterprise_slug}`}>
              {enterprise_name}
            </Link>
          </span>
        )}
      </div>

      {/*============== START OF BILLING POLICIES SECTION ==============*/}
      {/*
        today, overages is the only billing policy
        if more billing policies are added in the future, the conditions need to be modified/removed
      */}
      {showOveragesPolicy && (
        <Box
          data-hpc
          sx={{
            display: 'flex',
            flexDirection: 'column',
            gap: 'var(--stack-gap-normal)',
            marginBottom: 3,
          }}
        >
          <SectionHeading name="Billing" />
          <BoxSection>
            <OveragesPolicy />
          </BoxSection>
        </Box>
      )}
      {/*============== END OF BILLING POLICIES SECTION ==============*/}

      {/*============== START OF FEATURES POLICIES SECTION ==============*/}
      <Box
        data-hpc
        sx={{
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--stack-gap-normal)',
          marginBottom: 3,
        }}
      >
        <SectionHeading name="Features" />
        <BoxSection>
          {copilot_for_dotcom_visible && <CopilotForDotcomPolicy />}
          {showSparkPolicy && <GeneralPolicy policyName={'spark' as keyof CopilotForBusinessPoliciesPayload} />}
          <EditorChatPolicy />
          {showEditorPreviewFeatures && <EditorPreviewFeaturesPolicy />}
          <MobileChatPolicy />
          <CopilotCLIPolicy />
          {showCopilotDesktopPolicy && <CopilotDesktopPolicy />}
          {show_copilot_extensions_policy && <CopilotExtensionsPolicy />}
          {copilot_bing_visible && <BingGitHubChatPolicy />}
          <CopilotUsageMetricsPolicy />
          {showSweAgentPolicy && <GeneralPolicy policyName={'swe_agent' as keyof CopilotForBusinessPoliciesPayload} />}
          {showMcpPolicy && <GeneralPolicy policyName={'mcp' as keyof CopilotForBusinessPoliciesPayload} />}
        </BoxSection>
      </Box>
      {/*============== END OF FEATURES POLICIES SECTION ==============*/}

      {/*============== START OF PRIVACY POLICIES SECTION ==============*/}
      <Box
        data-hpc
        sx={{
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--stack-gap-normal)',
          marginBottom: 3,
        }}
      >
        <SectionHeading name="Privacy" />
        <BoxSection>
          <SnippyPolicy />
          {show_copilot_telemetry_policy && <CopilotTelemetryPolicy />}
        </BoxSection>
      </Box>
      {/*============== END OF PRIVACY POLICIES SECTION ==============*/}

      <Box
        data-hpc
        sx={{
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--stack-gap-normal)',
          marginBottom: 3,
        }}
      >
        <Text as="p" sx={{color: 'fg.muted'}} data-testid="cb-policies-footnotes">
          {' '}
          {plan !== 'enterprise' && (
            <FeaturesForDataRetention copilot_for_dotcom_visible={copilot_for_dotcom_visible} />
          )}
          If preview features are enabled, you agree to{' '}
          <Link href="https://docs.github.com/site-policy/github-terms/github-copilot-pre-release-license-terms" inline>
            pre-release terms
          </Link>
          . For more information about the data your organization receives regarding your use of GitHub Copilot, please
          review{' '}
          <Link href={docsUrls.generalPrivacyStatement} inline>
            GitHub&apos;s Privacy Statement
          </Link>
          .
        </Text>
      </Box>
    </>
  )
}

function CopilotForDotcomPolicy() {
  const isCopilotChatGA = useFeatureFlag('copilot_chat_dotcom_ga')
  const isSparkEnabled = useFeatureFlag('copilot_workbench')
  const data = useUIAspectFromRoute('copilot_for_dotcom')
  const {copilot_plan: plan} = useRoutePayload<CopilotForBusinessPoliciesPayload>()
  const isEnterprisePlan = plan === 'enterprise'

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable

  // Determines what list separate to use depending on which features can be enabled by the organization
  const copilotCodeReviewListSeparator = isEnterprisePlan || isSparkEnabled ? ', ' : ', and'
  const enterprisePlanListSeparator = isSparkEnabled ? ', ' : ', and'

  return (
    <Box sx={{display: 'flex', flexDirection: 'column', width: '100%'}}>
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: selected?.value === 'enabled' ? 'start' : 'center',
        }}
      >
        <div data-testid="cfb-policies-dotcom-bundle-feature">
          <PreviewFeatureHeading title="Copilot in GitHub.com" beta={!isEnterprisePlan && !isCopilotChatGA} />
          <div>
            If enabled, members of this organization can use{' '}
            <Link
              href="https://docs.github.com/copilot/github-copilot-enterprise/copilot-chat-in-github/about-github-copilot-chat"
              inline
            >
              Copilot Chat in GitHub.com
            </Link>
            ,{' '}
            <Link
              href="https://docs.github.com/copilot/github-copilot-enterprise/copilot-pull-request-summaries/about-copilot-pull-request-summaries"
              inline
            >
              Copilot for pull requests
            </Link>
            {copilotCodeReviewListSeparator}{' '}
            <Link
              href="https://docs.github.com/en/enterprise-cloud@latest/copilot/using-github-copilot/code-review/using-copilot-code-review"
              inline
            >
              Copilot code review
            </Link>
            {isEnterprisePlan && (
              <>
                {enterprisePlanListSeparator}{' '}
                <Link
                  href="https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-docset-management/about-copilot-docset-management"
                  inline
                >
                  knowledge base search
                </Link>
              </>
            )}
            {isSparkEnabled && (
              <>
                , and{' '}
                <Link href="https://gh.io/responsible-use-of-github-spark" inline>
                  Spark
                </Link>
              </>
            )}
            .
          </div>
          {selected?.value === 'enabled' && <UserFeedbackPolicy />}
          {selected?.value === 'enabled' && <BetaFeaturesPolicy />}
        </div>
        {disabled ? (
          <Box
            as="span"
            sx={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              gap: 1,
            }}
            data-testid="cfb-policies-dotcom-feature-locked"
          >
            <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
          </Box>
        ) : (
          <ActionMenuButton
            title={selected?.title ?? 'Disabled'}
            options={options}
            onSelect={onSelect}
            disabled={disabled}
            loading={loading}
            data-testid="cfb-policies-dotcom-bundle-feature-button"
          />
        )}
      </Box>
    </Box>
  )
}

function BingGitHubChatPolicy() {
  const data = useUIAspectFromRoute('bing_github_chat')

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable
  if (!data.visible) return null

  return (
    <>
      <div data-testid="cfb-policies-bing-feature" style={{maxWidth: 750}}>
        <SubtleHeading>
          <span>Copilot can search the web</span>
        </SubtleHeading>
        Copilot can answer questions about new trends and give improved answers, via Bing. See{' '}
        <Link href="https://privacy.microsoft.com/en-us/privacystatement" target="_blank" rel="noreferrer" inline>
          Microsoft Privacy Statement
        </Link>
        .
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-bing-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-bing-feature-button"
        />
      )}
    </>
  )
}

function UserFeedbackPolicy() {
  const org = useEnsureOrgName()
  const data = useUIAspectFromRoute('copilot_user_feedback_opt_in')

  const {addToast} = useToastContext()
  const useCopilotSettingsMutation = useCreateMutator(seatManagementEndpoint, {org})
  // eslint-disable-next-line react-hooks/react-compiler
  const [updateOption, loading] = useCopilotSettingsMutation<Record<string, string>, {success: boolean}>({
    resource: 'policies',
    method: 'PUT',
  })

  const onChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const isFeedbackEnabled = event.target.checked
      updateOption({
        payload: {[data.manages]: isFeedbackEnabled ? 'enabled' : 'disabled'},
        onError(e) {
          let message = 'Something went wrong. Please try again later.'
          if (e && typeof e === 'object' && 'message' in e) message = String(e.message)

          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({message, role: 'alert', type: 'error'})
        },
        onComplete(res) {
          if (res && res.success) {
            // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
            addToast({
              message: `User feedback is now ${isFeedbackEnabled ? 'enabled' : 'disabled'}`,
              role: 'alert',
              type: 'success',
            })
          }
        },
      })
    },
    [updateOption, addToast, data.manages],
  )

  const disabled = !data.configurable
  if (!data.visible) return null

  return (
    <Box as="form" sx={{mt: 2, pl: 3}}>
      <FormControl disabled={disabled || loading}>
        <Checkbox onChange={onChange} defaultChecked={data.enabled} data-testid="cfb-policies-feedback-checkbox" />
        <FormControl.Label sx={{display: 'flex', alignItems: 'center', mb: 2}}>
          Opt in to free text user feedback collection
        </FormControl.Label>
        <FormControl.Caption sx={{fontSize: 1}}>
          <p>
            Enables user feedback collection on Copilot features in github.com. This feedback may include sensitive
            information.
          </p>
        </FormControl.Caption>
      </FormControl>
    </Box>
  )
}

function CopilotCLIPolicy() {
  const data = useUIAspectFromRoute('cli')

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable

  return (
    <>
      <div data-testid="cfb-policies-cli-feature">
        <PreviewFeatureHeading title="Copilot in the CLI" beta={false} />
        If enabled, members of this organization will get{' '}
        <Link href="https://docs.github.com/copilot/github-copilot-in-the-cli/using-github-copilot-in-the-cli" inline>
          GitHub Copilot assistance in terminal
        </Link>
        {' and '}
        <br />
        <Link href="https://learn.microsoft.com/en-us/windows/terminal/terminal-chat" inline>
          {'Windows Terminal Chat'}
        </Link>
        .
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-cli-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-cli-feature-button"
        />
      )}
    </>
  )
}

function CopilotDesktopPolicy() {
  const data = useUIAspectFromRoute('desktop')
  const copilotDesktopNoPreviewBadge = useFeatureFlag('copilot_desktop_no_preview_badge')

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable

  return (
    <>
      <div data-testid="cfb-policies-desktop-feature">
        <PreviewFeatureHeading title="Copilot in GitHub Desktop" beta={!copilotDesktopNoPreviewBadge} />
        If enabled, members of this organization will get{' '}
        <Link
          href="https://docs.github.com/en/copilot/responsible-use-of-github-copilot-features/responsible-use-of-github-copilot-in-github-desktop"
          inline
        >
          GitHub Copilot assistance in GitHub Desktop
        </Link>
        .
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-desktop-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-desktop-feature-button"
        />
      )}
    </>
  )
}

function EditorChatPolicy() {
  const data = useUIAspectFromRoute('editor_chat')

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable

  return (
    <>
      <div data-testid="cfb-policies-editor-chat-feature">
        <SubtleHeading>
          <span>Copilot Chat in the IDE</span>
        </SubtleHeading>
        If enabled, members of this organization will have access to{' '}
        <Link href="https://docs.github.com/copilot/github-copilot-chat/using-github-copilot-chat-in-your-ide" inline>
          Copilot Chat in the IDE
        </Link>
        .
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-editor-chat-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Unknown'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-editor-chat-feature-button"
        />
      )}
    </>
  )
}

function MobileChatPolicy() {
  const data = useUIAspectFromRoute('mobile_chat')

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable

  return (
    <>
      <div data-testid="cfb-policies-mobile-chat-feature">
        <PreviewFeatureHeading title="Copilot Chat in GitHub Mobile" beta={false} />
        If enabled, members of this organization will have access to{' '}
        <Link href="https://github.co/copilot-chat-mobile-docs" inline>
          Copilot Chat in GitHub Mobile
        </Link>
        .
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-mobile-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Unknown'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-mobile-chat-feature-button"
        />
      )}
    </>
  )
}

function SnippyPolicy() {
  const data = useUIAspectFromRoute('snippy')

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
    defaultOption: {
      value: 'NA',
      id: 'unconfigured',
      title: 'Unconfigured',
    },
  })

  const disabled = !data.configurable

  return (
    <>
      <div data-testid="cfb-policies-snippy-feature">
        <SubtleHeading>Suggestions matching public code (duplication detection filter)</SubtleHeading>
        Copilot can allow or block suggestions matching public code.
      </div>
      {disabled ? (
        <span>
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Unknown'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
        />
      )}
    </>
  )
}

function CopilotExtensionsPolicy() {
  const data = useUIAspectFromRoute('copilot_extensions')

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable

  return (
    <>
      <div data-testid="cfb-policies-copilot-extensions-feature" style={{maxWidth: '80%'}}>
        <PreviewFeatureHeading title="Copilot Extensions" beta={false} />
        If enabled, extensions can access organization data per granted permissions. Data use is subject to extension
        provider&#39;s terms and privacy policy. The Duplication Detection Filter does not apply to extension responses.
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-copilot-extensions-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-copilot_extensions-feature-button"
        />
      )}
    </>
  )
}

function CopilotTelemetryPolicy() {
  const data = useUIAspectFromRoute('private_telemetry')

  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  // Always enable this until we support managing Copilot Custom Models from
  // enterprises.
  const disabled = false // !data.configurable

  return (
    <>
      <div data-testid="cfb-policies-copilot-org-private-telemetry-feature">
        <PreviewFeatureHeading title="Telemetry data collection" beta />
        Copilot will securely collect data from developers&apos; prompts and returned suggestions for custom model
        training.
      </div>
      {disabled ? (
        <span>
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-copilot-org-private-telemetry-feature-button"
        />
      )}
    </>
  )
}

function BetaFeaturesPolicy() {
  const org = useEnsureOrgName()
  const data = useUIAspectFromRoute('copilot_beta_features_opt_in')

  const {addToast} = useToastContext()
  const useCopilotSettingsMutation = useCreateMutator(seatManagementEndpoint, {org})
  // eslint-disable-next-line react-hooks/react-compiler
  const [updateOption, loading] = useCopilotSettingsMutation<Record<string, string>, {success: boolean}>({
    resource: 'policies',
    method: 'PUT',
  })

  const onChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const isBetaFeatureEnabled = event.target.checked
      updateOption({
        payload: {[data.manages]: isBetaFeatureEnabled ? 'enabled' : 'disabled'},
        onError(e) {
          let message = 'Something went wrong. Please try again later.'
          if (e && typeof e === 'object' && 'message' in e) message = String(e.message)

          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({message, role: 'alert', type: 'error'})
        },
        onComplete(res) {
          if (res && res.success) {
            // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
            addToast({
              message: `Preview features are now ${isBetaFeatureEnabled ? 'enabled' : 'disabled'}`,
              role: 'alert',
              type: 'success',
            })
          }
        },
      })
    },
    [updateOption, addToast, data.manages],
  )

  const disabled = !data.configurable
  if (!data.visible) return null

  return (
    <Box as="form" sx={{mt: 2, pl: 3}}>
      <FormControl disabled={disabled || loading}>
        <Checkbox onChange={onChange} defaultChecked={data.enabled} data-testid="cfb-policies-beta-features-checkbox" />
        <FormControl.Label sx={{display: 'flex', alignItems: 'center', mb: 2}}>
          Opt in to preview features
        </FormControl.Label>
        <FormControl.Caption sx={{fontSize: 1}}>
          <p>
            If enabled, members of this organization can use previews of new Copilot in GitHub.com features. See{' '}
            <Link href="https://docs.github.com/en/site-policy/github-terms/github-pre-release-license-terms" inline>
              {"GitHub's pre-release terms"}
            </Link>
            .
          </p>
        </FormControl.Caption>
      </FormControl>
    </Box>
  )
}

function CopilotUsageMetricsPolicy() {
  const data = useUIAspectFromRoute('copilot_usage_metrics_policy')
  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable

  if (!data.visible) {
    return null
  }

  return (
    <>
      <div data-testid="cfb-policies-copilot-usage-metrics-feature">
        <PreviewFeatureHeading title="Copilot Metrics API access" beta={false} />
        If enabled, organization administrations can query the{' '}
        <Link href="https://docs.github.com/en/rest/copilot/copilot-metrics?apiVersion=2022-11-28" inline>
          {'Copilot Metrics API'}
        </Link>{' '}
        for insights into Copilot usage.
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-copilot-usage-metrics-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-copilot-usage-metrics-control"
        />
      )}
    </>
  )
}

function EditorPreviewFeaturesPolicy() {
  const data = useUIAspectFromRoute('editor_preview_features')
  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
    defaultOption: {
      value: 'NA',
      id: 'unconfigured',
      title: 'Unconfigured',
    },
  })

  const disabled = !data.configurable

  if (!data.visible) {
    return null
  }

  return (
    <>
      <div data-testid="cfb-policies-editor-preview-features-feature">
        <PreviewFeatureHeading title="Editor preview features" beta />
        If enabled, members of this organization will have access to editor preview features.
        <br />
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-editor-preview-features-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-editor-preview-features-control"
        />
      )}
    </>
  )
}

function OveragesPolicy() {
  const data = useUIAspectFromRoute('overages')
  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
  })

  const disabled = !data.configurable

  if (!data.visible) {
    return null
  }

  return (
    <>
      <div data-testid="cfb-policies-copilot-overages-feature">
        <PreviewFeatureHeading title="Additional Copilot premium requests" beta={false} />
        If enabled, additional premium requests beyond the included amount for each license will be billed.{' '}
        <Link href="" inline>
          {'Learn more.'}
        </Link>
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-copilot-overages-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-copilot-overages-control"
        />
      )}
    </>
  )
}
