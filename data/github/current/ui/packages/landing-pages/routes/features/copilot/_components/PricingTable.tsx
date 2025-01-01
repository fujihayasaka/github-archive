import {ChevronDownIcon} from '@primer/octicons-react'
import {Box, Button, Grid, Label, Stack, Text} from '@primer/react-brand'
import {allFeatures} from './PricingData'
import type {Feature, FeatureGroup} from './PricingData'
import {analyticsEvent} from '../../../../lib/analytics'
import {useState, useRef} from 'react'
import PricingTableCell from './PricingTableCell'
import {isFeatureEnabled} from '@github-ui/feature-flags'

interface PricingTableProps {
  copilotProSignupPath: string
  copilotForBusinessSignupPath: string
  copilotEnterpriseSignupPath: string
  footnotesModifier?: number
}

export default function PricingTable({
  copilotProSignupPath,
  copilotForBusinessSignupPath,
  copilotEnterpriseSignupPath,
  footnotesModifier,
}: PricingTableProps) {
  const [expandedStates, setExpandedStates] = useState<{[key: string]: boolean}>({})
  const currentFootnote = useRef(0)
  const footnoteCounter = useRef(0)

  const isDetailsExpanded = (id: string) => {
    return expandedStates[id]
  }

  const toggleDetailsExpanded = (e: React.MouseEvent<HTMLElement>) => {
    const id = (e.target as HTMLElement).getAttribute('data-target-id')
    if (!id) return
    setExpandedStates(prev => ({...prev, [id]: !prev[id]}))
  }

  const handleFootnoteLinkClick = (e: React.MouseEvent<HTMLElement>, footnoteId: string) => {
    const target = e.currentTarget
    const footnoteTargetId = target.getAttribute('href')?.slice(1)
    if (!footnoteTargetId) return
    const footnoteTarget = document.getElementById(footnoteTargetId)
    if (!footnoteTarget) return
    const returnLink = footnoteTarget.querySelector('a[href^="#footnote-ref-"]')
    if (!returnLink) return
    returnLink.setAttribute('href', `#${footnoteId}`)
  }

  const featureFlags = {
    site_copilot_plans_ga: isFeatureEnabled('site_copilot_plans_ga'),
  }

  return (
    <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap js-toggler-container">
      <Grid.Column span={12}>
        <div role="table" className="lp-Pricing-table">
          <Stack
            direction="horizontal"
            gap={32}
            padding="none"
            className="border-bottom pb-4 mb-4 mb-md-0 lp-Pricing-table-header lp-Pricing-table-header-noAnchorNav z-3 top-0"
          >
            <Box className="flex-1 col-12 col-md-3">
              <Text size="500">Compare features</Text>
            </Box>
            <Stack
              role="rowgroup"
              direction="vertical"
              gap={4}
              padding="none"
              className="col-1 col-md-8 d-none d-md-flex"
            >
              <Stack role="row" direction="horizontal" gap={32} padding="none">
                <Stack role="columnheader" padding="none" gap="none" className="position-absolute">
                  <span className="sr-only">Features</span>
                </Stack>

                {/* Copilot Free */}
                <Stack role="columnheader" padding="none" gap={12} className="col-4 text-center px-4 px-md-0 d-flex">
                  <span className="h6-mktg text-semibold">Free</span>
                </Stack>

                {/* Copilot Pro */}
                <Stack role="columnheader" padding="none" gap={12} className="col-4 text-center px-4 px-md-0 d-flex">
                  <span className="h6-mktg text-semibold">Pro</span>
                </Stack>

                {/* Copilot Business */}
                <Stack role="columnheader" padding="none" gap={12} className="col-4 text-center px-4 px-md-0 d-flex">
                  <span className="h6-mktg text-semibold">Business</span>
                </Stack>

                {/* Copilot Enterprise */}
                <Stack role="columnheader" padding="none" gap={12} className="col-4 text-center px-4 px-md-0 d-flex">
                  <span className="h6-mktg text-semibold">Enterprise</span>
                </Stack>
              </Stack>

              <Stack role="row" direction="horizontal" gap={32} padding="none">
                <Stack role="rowheader" padding="none" gap="none" className="position-absolute">
                  <span className="sr-only">Pricing</span>
                </Stack>

                {/* Copilot Pro */}
                <Stack role="cell" padding="none" gap={12} className="col-4 text-center px-4 px-md-0 d-flex">
                  <Text as="span" size="100" weight="normal" className="is-sansSerifAlt">
                    $0
                  </Text>
                </Stack>

                {/* Copilot Pro */}
                <Stack role="cell" padding="none" gap={12} className="col-4 text-center px-4 px-md-0 d-flex">
                  <Text as="span" size="100" weight="normal" className="is-sansSerifAlt">
                    $10 <span className="lp-Pricing-text-muted">per month</span>
                  </Text>
                </Stack>

                {/* Copilot Business */}
                <Stack role="cell" padding="none" gap={12} className="col-4 text-center px-4 px-md-0 d-flex">
                  <Text as="span" size="100" weight="normal" className="is-sansSerifAlt">
                    $19 <span className="lp-Pricing-text-muted">per user / month</span>
                  </Text>
                </Stack>

                {/* Copilot Enterprise */}
                <Stack role="cell" padding="none" gap={12} className="col-4 text-center px-4 px-md-0 d-none d-md-flex">
                  <Text as="span" size="100" weight="normal" className="is-sansSerifAlt">
                    $39 <span className="lp-Pricing-text-muted">per user / month</span>
                  </Text>
                </Stack>
              </Stack>
            </Stack>
          </Stack>

          <Stack direction="vertical" gap={32} padding="none">
            {
              // eslint-disable-next-line react-compiler/react-compiler
              allFeatures(featureFlags).map((group: FeatureGroup, i) => {
                const groupId = group.title.replace(/\s+/g, '-').toLowerCase()
                const isExpanded = isDetailsExpanded(groupId)

                return (
                  <Stack
                    role="rowgroup"
                    direction="vertical"
                    gap="none"
                    padding="none"
                    // eslint-disable-next-line @eslint-react/no-array-index-key
                    key={`rowgroup-${i}`}
                    className={isExpanded ? 'expanded' : ''}
                  >
                    <div role="row">
                      <div role="cell" className="text-semibold mt-0 mt-md-5 pb-4 pb-md-3 d-none d-md-block">
                        <Text size="300" weight="semibold">
                          {group.title}
                        </Text>
                      </div>
                      <div role="cell" className="d-md-none">
                        <button
                          type="button"
                          aria-expanded={isExpanded}
                          data-target-id={group.title.replace(/\s+/g, '-').toLowerCase()}
                          className="position-relative text-semibold width-full lp-Pricing-features-toggle-btn border-bottom mt-0 mt-md-5 pb-4 pb-md-3"
                          onClick={toggleDetailsExpanded}
                          {...analyticsEvent({
                            action: `expand_${groupId}`,
                            tag: 'icon',
                            location: 'compare_features',
                            context: 'mobile',
                          })}
                        >
                          <Text size="300" weight="semibold" className="events-none">
                            {group.title}
                            <div className="lp-Pricing-features-icon position-absolute top-0 right-0 d-md-none">
                              <ChevronDownIcon />
                            </div>
                          </Text>
                        </button>
                      </div>
                    </div>

                    <div className="lp-Pricing-features-box">
                      {group.features.map((feature: Feature, j) => {
                        const footnote = feature.footnote ? parseInt(feature.footnote) : 0
                        const footnoteModified = footnote && footnotesModifier ? footnote + footnotesModifier : footnote
                        if (footnote && currentFootnote.current !== footnote) {
                          currentFootnote.current = footnote
                          footnoteCounter.current = 0
                        }
                        if (footnote) footnoteCounter.current++
                        const footnoteId = footnote ? `footnote-ref-${footnoteModified}-${footnoteCounter.current}` : ''

                        return (
                          <Stack
                            // eslint-disable-next-line @eslint-react/no-array-index-key
                            key={`row-${j}`}
                            direction={{narrow: 'vertical', regular: 'horizontal'}}
                            gap={{narrow: 16, regular: 32}}
                            padding="none"
                            className="border-bottom py-4 py-md-3"
                            role="row"
                          >
                            <Box role="rowheader" className="flex-1 col-12 col-md-3">
                              <Text size="200" weight="normal" className="lp-Pricing-table-rowheader">
                                {feature.label && (
                                  <div className="lp-Pricing-table-label-wrap">
                                    <div className="lp-ConicGradientBorder lp-ConicGradientBorder-label lp-ConicGradientBorder-label-mini d-inline-block">
                                      <Label
                                        size="medium"
                                        color="purple-red"
                                        className="lp-ConicGradientBorder-label-inner"
                                      >
                                        {feature.label}
                                      </Label>
                                    </div>
                                  </div>
                                )}
                                {feature.title}{' '}
                                {feature.footnote && (
                                  <sup>
                                    <a
                                      href={`#footnote-${footnoteModified}`}
                                      onClick={e => handleFootnoteLinkClick(e, footnoteId)}
                                      id={footnoteId}
                                    >
                                      {footnoteModified}
                                    </a>
                                  </sup>
                                )}
                                {feature.description}
                              </Text>
                            </Box>
                            <Stack
                              direction={{narrow: 'vertical', regular: 'horizontal'}}
                              gap={{narrow: 16, regular: 32}}
                              padding="none"
                              className="col-12 col-md-8 flex-items-center"
                            >
                              <PricingTableCell planName="Free" value={feature.free} />
                              <PricingTableCell planName="Pro" value={feature.pro} />
                              <PricingTableCell planName="Business" value={feature.business} />
                              <PricingTableCell planName="Enterprise" value={feature.enterprise} />
                            </Stack>
                          </Stack>
                        )
                      })}
                    </div>
                  </Stack>
                )
              })
            }
          </Stack>

          <Stack role="rowgroup" direction="vertical" gap={32} padding="none" className="d-none d-lg-flex">
            <Stack role="row" direction="horizontal" gap={32} padding="none" className="d-flex pt-4">
              <Box role="rowheader" className="flex-1 col-3">
                <span className="sr-only">How to get started</span>
              </Box>
              <Stack direction="horizontal" gap={32} padding="none" className="col-12 col-md-8">
                {/* Copilot Free */}
                <Stack role="cell" padding="none" gap={12} className="col-4 text-center px-4 px-md-0">
                  <Stack direction={{narrow: 'vertical', wide: 'vertical'}} gap={12} padding="none">
                    <Button
                      className="lp-Pricing-table-button"
                      as="a"
                      href="https://github.com/copilot"
                      block
                      variant="primary"
                      {...analyticsEvent({
                        action: 'get_started',
                        tag: 'button',
                        context: 'free_plan',
                        location: 'features_table',
                      })}
                    >
                      Get started
                    </Button>
                  </Stack>
                </Stack>

                {/* Copilot Pro */}
                <Stack role="cell" padding="none" gap={12} className="col-4 text-center px-4 px-md-0">
                  <Stack direction={{narrow: 'vertical', wide: 'vertical'}} gap={12} padding="none">
                    <Button
                      className="lp-Pricing-table-button"
                      as="a"
                      href={copilotProSignupPath}
                      block
                      variant="primary"
                      {...analyticsEvent({
                        action: 'get_started',
                        tag: 'button',
                        context: 'pro_plan',
                        location: 'features_table',
                      })}
                    >
                      Get started
                    </Button>
                  </Stack>
                </Stack>

                {/* Copilot Business */}
                <Stack role="cell" padding="none" gap={12} className="col-4 text-center px-4 px-md-0">
                  <Stack direction={{narrow: 'vertical', wide: 'vertical'}} gap={12} padding="none">
                    <Button
                      className="lp-Pricing-table-button"
                      as="a"
                      href={copilotForBusinessSignupPath}
                      block
                      variant="primary"
                      {...analyticsEvent({
                        action: 'get_started',
                        tag: 'button',
                        context: 'business_plan',
                        location: 'features_table',
                      })}
                    >
                      Get started
                    </Button>
                  </Stack>
                </Stack>

                {/* Copilot Enterprise */}
                <Stack role="cell" padding="none" gap={12} className="col-4 text-center px-4 px-md-0">
                  <Stack direction={{narrow: 'vertical', wide: 'vertical'}} gap={12} padding="none">
                    <Button
                      className="lp-Pricing-table-button"
                      as="a"
                      href={copilotEnterpriseSignupPath}
                      variant="primary"
                      {...analyticsEvent({
                        action: 'get_started',
                        tag: 'button',
                        context: 'enterprise_plan',
                        location: 'features_table',
                      })}
                    >
                      Get started
                    </Button>
                  </Stack>
                </Stack>
              </Stack>
            </Stack>
          </Stack>
        </div>
      </Grid.Column>
    </Grid>
  )
}
