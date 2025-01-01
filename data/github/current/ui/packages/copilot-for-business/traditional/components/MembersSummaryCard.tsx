import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {currency as formatCurrency} from '@github-ui/formatters'
import {AnchoredOverlay, Box, Button, Heading, IconButton, Link, Popover, Text} from '@primer/react'
import {CopilotCard} from './Ui'
import {InfoIcon} from '@primer/octicons-react'
import {useMemo, useState} from 'react'
import {dismissUserNoticePath} from '@github-ui/paths'
import {verifiedFetch} from '@github-ui/verified-fetch'
import type {CopilotForBusinessTrial, PlanText, SeatBreakdown} from '../../types'
import {capitalizeFirstLetter} from '../../helpers/text'
import {planCost} from '../../helpers/plan'

type Props = {
  slug: string
  renderCopilotInsightsBanner: boolean
  adoptionMetrics: {
    total: number
    active: number
    inactive: number
    dormant: number
  }
  planText: PlanText
  seatBreakdown: SeatBreakdown
  trial?: CopilotForBusinessTrial
}

type InsightProps = {
  renderCopilotInsightsBanner: boolean
}

const FALLBACK = 'No data yet'

export function MembersSummaryCard(props: Props) {
  const {seatBreakdown, planText} = props
  const {total, active, inactive, dormant} = props.adoptionMetrics
  const seatCount = seatBreakdown.seats_billed + seatBreakdown.seats_pending
  const trial = props.trial ?? ({} as CopilotForBusinessTrial)
  const {has_trial, active: is_active, ends_at, copilot_plan} = trial

  const isValidDate = (dateString: string): boolean => {
    const date = new Date(dateString)
    return !isNaN(date.getTime())
  }

  const formattedEndDate = useMemo(() => {
    if (!ends_at || !isValidDate(ends_at)) return ''

    return new Date(ends_at).toLocaleDateString('en-US', {
      month: 'long',
      day: 'numeric',
      year: 'numeric',
    })
  }, [ends_at])

  const renderCostText = () => {
    let text = ''
    if (has_trial && copilot_plan === 'business') {
      text = 'Free'
    } else if (seatCount) {
      text = `${formatCurrency(seatCount * planCost(planText))}`
    }
    return text || FALLBACK
  }

  const renderPerSeatText = () => {
    let text = ''
    if (has_trial && is_active) {
      text = `Free Copilot ${capitalizeFirstLetter(copilot_plan)} trial until ${formattedEndDate}`
    } else if (!has_trial) {
      text = `Each assigned license is $${planCost(planText)} per month`
    }
    return text
  }

  return (
    <Box
      as="section"
      sx={{display: 'flex', width: '100%', gap: 3, marginBottom: 2, marginTop: 3}}
      aria-label="Insights"
    >
      <CopilotCard
        sx={{
          display: 'flex',
          flexDirection: ['column', 'row'],
          alignSelf: 'start',
          width: '100%',
        }}
      >
        <Box sx={{display: 'flex', flex: 2, flexDirection: 'column'}}>
          <Box sx={{display: 'flex', flex: 1, justifyContent: 'space-between'}}>
            <Box sx={{display: 'flex'}}>
              <Text as="h4" sx={{fontWeight: 600, fontSize: 14}}>
                Members
              </Text>
              <MembersInfoOverlay />
            </Box>
            <Box sx={{marginRight: 4}}>
              <Link
                href={`${ssrSafeLocation.origin}/orgs/${props.slug}/insights/metrics/copilot-user-onboarding`}
                inline
              >
                View insights
              </Link>
              <InsightPopover renderCopilotInsightsBanner={props.renderCopilotInsightsBanner} />
            </Box>
          </Box>
          <Box sx={{display: 'flex', flex: 3, marginTop: 1, alignItems: 'center', justifyContent: 'space-between'}}>
            <Box sx={{flex: 1, borderRight: '1px solid', borderColor: 'border.default'}}>
              <Text as="span" sx={{fontSize: 20}} data-testid="members-total">
                {total}
              </Text>
              <Text as="p" sx={{color: 'fg.muted', fontSize: 14, marginBottom: 0, marginTop: 1}}>
                Total
              </Text>
            </Box>
            <Box sx={{flex: 1, borderRight: '1px solid', borderColor: 'border.default', marginLeft: 3}}>
              <Text as="span" sx={{fontSize: 20}} data-testid="members-dormant">
                {dormant}
              </Text>
              <Text as="p" sx={{color: 'fg.muted', fontSize: 14, marginBottom: 0, marginTop: 1}}>
                Dormant
              </Text>
            </Box>
            <Box sx={{flex: 1, borderRight: '1px solid', borderColor: 'border.default', marginLeft: 3}}>
              <Text as="span" sx={{fontSize: 20}} data-testid="members-inactive">
                {inactive}
              </Text>
              <Text as="p" sx={{color: 'fg.muted', fontSize: 14, marginBottom: 0, marginTop: 1}}>
                Inactive
              </Text>
            </Box>
            <Box sx={{flex: 1, paddingLeft: 3}}>
              <Text as="span" sx={{fontSize: 20}} data-testid="members-active">
                {active}
              </Text>
              <Text as="p" sx={{color: 'fg.muted', fontSize: 14, marginBottom: 0, marginTop: 1}}>
                Active
              </Text>
            </Box>
          </Box>
        </Box>
        <Box
          sx={{
            display: 'flex',
            flex: 1,
            flexDirection: 'column',
            borderLeft: '1px solid',
            borderColor: 'border.default',
            paddingLeft: 3,
          }}
        >
          <Box sx={{display: 'flex', flex: 1, justifyContent: 'space-between'}}>
            <Text as="p" sx={{fontWeight: 600, fontSize: 14}}>
              Estimated next payment
            </Text>
            <Link
              sx={{marginRight: 2}}
              href={`${ssrSafeLocation.origin}/organizations/${props.slug}/settings/billing/summary`}
              inline
            >
              View billing
            </Link>
          </Box>
          <Box sx={{width: '100%', flex: 3, marginTop: 1}}>
            <Text as="span" sx={{fontSize: 20}} data-testid="members-cost">
              {renderCostText()}
            </Text>
            <Text
              as="p"
              sx={{color: 'fg.muted', fontSize: 14, marginBottom: 0, marginTop: 1}}
              data-testid="members-per-seat"
            >
              {renderPerSeatText()}
            </Text>
          </Box>
        </Box>
      </CopilotCard>
    </Box>
  )
}

function MembersInfoOverlay() {
  const [open, setOpen] = useState(false)
  const cfbHelpLink =
    'https://docs.github.com/enterprise-cloud@latest/copilot/overview-of-github-copilot/about-github-copilot-for-business'

  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => setOpen(false)}
      side="outside-top"
      align="center"
      data-testid="members-info-overlay"
      renderAnchor={anchorProps => {
        return (
          // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
          <IconButton
            {...anchorProps}
            icon={InfoIcon}
            variant="invisible"
            aria-label="More information"
            data-testid="members-info-overlay-button"
            aria-labelledby={undefined}
            unsafeDisableTooltip
            sx={{position: 'relative', top: '-6px', marginLeft: '4px'}}
          />
        )
      }}
      overlayProps={{
        sx: {width: 240, height: 260},
      }}
    >
      <Box sx={{padding: 4}}>
        <Heading as="h4" sx={{fontWeight: 600, fontSize: 14, marginBottom: 3}}>
          GitHub Copilot members
        </Heading>
        <Text as="p" sx={{color: 'fg.muted', fontSize: 14, marginBottom: 3}}>
          Each member is assigned a Copilot license. You can add or remove members at any time during the billing cycle
          to optimize license usage and allocation based on member activity.
        </Text>
        <Link href={cfbHelpLink} sx={{fontSize: 14}}>
          Learn more about licenses
        </Link>
      </Box>
    </AnchoredOverlay>
  )
}

function InsightPopover(props: InsightProps) {
  const [showCopilotInsightsPopover, setShowCopilotInsightsPopover] = useState(props.renderCopilotInsightsBanner)
  const handleDismissForever = () => {
    verifiedFetch(dismissUserNoticePath({noticeName: 'copilot_insights_banner'}), {method: 'POST'})
    setShowCopilotInsightsPopover(false)
  }

  if (!showCopilotInsightsPopover) return null

  return (
    <Popover
      relative={false}
      open={showCopilotInsightsPopover}
      caret="top"
      sx={{transform: 'translateX(-30%)'}}
      data-testid="insight-popover"
    >
      <Popover.Content
        sx={{
          color: 'fg.default',
          marginTop: 2,
          width: 240,
        }}
      >
        <Heading as="h4" sx={{fontWeight: 600, fontSize: 14, marginBottom: 3}}>
          Introducing Copilot Insights
        </Heading>
        <Text as="p" sx={{color: 'fg.muted', fontSize: 14, marginBottom: 3}}>
          You can now track how Copilot is being used across your organization with clear, actionable data. Get insights
          into activity, usage patterns, and more.
        </Text>
        <Button onClick={handleDismissForever} data-testid="dismiss-forever-button">
          OK, got it
        </Button>
      </Popover.Content>
    </Popover>
  )
}
