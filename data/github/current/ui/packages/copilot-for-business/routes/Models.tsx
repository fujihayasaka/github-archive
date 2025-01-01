import {clsx} from 'clsx'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ShieldLockIcon} from '@primer/octicons-react'
import {Box, Link, Text} from '@primer/react'
import {ActionMenuButton} from '../traditional/components/ActionMenuButton'
import {BoxSection, PageHeading} from '../traditional/components/Ui'
import type {CopilotForBusinessPoliciesPayload} from '../types'
import styles from './Policies.module.css'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import GeneralPolicy from '../components/GeneralPolicy'
import PreviewFeatureHeading from '../components/PreviewFeatureHeading'
import {useUIAspectFromRoute} from '../hooks/use-ui-aspect-from-route'
import {useOptions} from '../hooks/use-options'

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

export default function ModelsPage() {
  const copilot_for_dotcom_visible = useUIAspectFromRoute('copilot_for_dotcom').visible
  const showAChat = useUIAspectFromRoute('a_chat').visible
  const showAF = useUIAspectFromRoute('a_f').visible
  const showAFOS = useUIAspectFromRoute('afos').visible
  const showAL = useUIAspectFromRoute('al').visible
  const showGChat = useUIAspectFromRoute('g_chat').visible
  const showGTF = useUIAspectFromRoute('g_tf').visible
  const showGTFF = useUIAspectFromRoute('gtff').visible
  const showO1 = useUIAspectFromRoute('o1').visible
  const showO3 = useUIAspectFromRoute('o3').visible
  const showOFF = useUIAspectFromRoute('o_ff').visible
  const showOFM = useUIAspectFromRoute('o_fm').visible
  const showOF = useUIAspectFromRoute('o_f').visible
  const showOT = useUIAspectFromRoute('o_t').visible
  const showOFO = useUIAspectFromRoute('ofo').visible
  const payload = useRoutePayload<CopilotForBusinessPoliciesPayload>()
  const showPolicyFormRefactor = useFeatureFlag('copilot_policy_form_refactor')
  const {enterprise_name, enterprise_slug, copilot_plan: plan, docsUrls} = payload
  return (
    <>
      <PageHeading name="GitHub Copilot models" />
      <div className={clsx(styles.topBox, 'mb-3')}>
        <span className={clsx(styles.muted, 'mb-3')}>
          You can manage policies and grant access to Copilot models for all members with access.
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
      <Box
        data-hpc
        sx={{
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--stack-gap-normal)',
        }}
      >
        <BoxSection>
          {showAChat && <AChatPolicy />}
          {showAF &&
            (showPolicyFormRefactor ? (
              <GeneralPolicy policyName={'a_f' as keyof CopilotForBusinessPoliciesPayload} />
            ) : (
              <AFPolicy />
            ))}
          {showAFOS && <GeneralPolicy policyName={'afos' as keyof CopilotForBusinessPoliciesPayload} />}
          {showAL && <GeneralPolicy policyName={'al' as keyof CopilotForBusinessPoliciesPayload} />}
          {showGChat && <GChatPolicy />}
          {showGTF && <GeneralPolicy policyName={'g_tf' as keyof CopilotForBusinessPoliciesPayload} />}
          {showGTFF && <GeneralPolicy policyName={'gtff' as keyof CopilotForBusinessPoliciesPayload} />}
          {showO1 && <O1Policy />}
          {showOT && <GeneralPolicy policyName={'o_t' as keyof CopilotForBusinessPoliciesPayload} />}
          {showO3 && <O3Policy />}
          {showOFM && <GeneralPolicy policyName={'o_fm' as keyof CopilotForBusinessPoliciesPayload} />}
          {showOFO && <GeneralPolicy policyName={'ofo' as keyof CopilotForBusinessPoliciesPayload} />}
          {showOFF && <OFFPolicy />}
          {showOF && <OFPolicy />}
        </BoxSection>
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

function AChatPolicy() {
  const data = useUIAspectFromRoute('a_chat')
  const aChatGA = useUIAspectFromRoute('a_chat_ga')
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
      <div data-testid="cfb-policies-a-chat-feature">
        <PreviewFeatureHeading title="Anthropic Claude 3.5 Sonnet in Copilot" beta={!aChatGA} />
        If enabled, members of this organization will have access to the latest Claude 3.5 Sonnet model.
        <br />
        <Link href="https://docs.github.com/copilot/using-github-copilot/using-claude-sonnet-in-github-copilot" inline>
          Learn more about how GitHub Copilot serves Claude 3.5 Sonnet.
        </Link>
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-a-chat-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-a-chat-control"
        />
      )}
    </>
  )
}

function AFPolicy() {
  const data = useUIAspectFromRoute('a_f')
  const afGA = useUIAspectFromRoute('a_f_ga')
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
      <div data-testid="cfb-policies-a-f-feature">
        <PreviewFeatureHeading title="Anthropic Claude 3.7 Sonnet in Copilot" beta={!afGA} />
        If enabled, members of this organization will have access to the latest Claude 3.7 Sonnet model.
        <br />
        <Link href="https://docs.github.com/copilot/using-github-copilot/using-claude-sonnet-in-github-copilot" inline>
          Learn more about how GitHub Copilot serves Claude 3.7 Sonnet.
        </Link>
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-a-f-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-a-f-control"
        />
      )}
    </>
  )
}

function GChatPolicy() {
  const data = useUIAspectFromRoute('g_chat')
  const gChatGA = useUIAspectFromRoute('g_chat_ga')
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
      <div data-testid="cfb-policies-g-chat-feature">
        <PreviewFeatureHeading title="Google Gemini 2.0 Flash in Copilot" beta={!gChatGA} />
        If enabled, members of this organization will have access to the Gemini 2.0 Flash model in Copilot.
        <br />
        <Link
          href="https://docs.github.com/en/copilot/using-github-copilot/ai-models/using-gemini-flash-in-github-copilot"
          inline
        >
          Learn more about how GitHub Copilot serves Gemini 2.0 Flash.
        </Link>
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-g-chat-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-g-chat-control"
        />
      )}
    </>
  )
}

function O1Policy() {
  const data = useUIAspectFromRoute('o1')
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
      <div data-testid="cfb-policies-o1-feature">
        <PreviewFeatureHeading title="OpenAI o1 models in Copilot" beta />
        If enabled, members of this organization will have access to use the o1 models in Copilot Chat.
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-o1-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-o1-control"
        />
      )}
    </>
  )
}

function O3Policy() {
  const data = useUIAspectFromRoute('o3')
  const o3GA = useUIAspectFromRoute('o3_mini_ga')

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
      <div data-testid="cfb-policies-o3-feature">
        <PreviewFeatureHeading title="OpenAI o3-mini in Copilot" beta={!o3GA} />
        If enabled, members of this organization will have access to the OpenAI o3-mini model.
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-o3-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-o3-control"
        />
      )}
    </>
  )
}

function OFFPolicy() {
  const data = useUIAspectFromRoute('o_ff')
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
      <div data-testid="cfb-policies-o-ff-feature">
        <PreviewFeatureHeading title="OpenAI GPT-4.5 model in Copilot" beta />
        If enabled, members of this organization will have access to the OpenAI GPT-4.5 model in Copilot Chat.
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-o-ff-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-o-ff-control"
        />
      )}
    </>
  )
}

function OFPolicy() {
  const data = useUIAspectFromRoute('o_f')
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
      <div data-testid="cfb-policies-o-f-feature">
        <PreviewFeatureHeading title="TEMP O_F HEADER" beta />
        TEMP O_F
      </div>
      {disabled ? (
        <span data-testid="cfb-policies-o-f-feature-locked">
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid="cfb-policies-o-f-control"
        />
      )}
    </>
  )
}
