import type {CopilotMetricsInsightsPayload} from '../routes/CopilotMetricsInsightsViewer'
import {CopilotMetricsDataType} from '../types/copilot-metrics'

export function getCopilotMetricsInsightsRoutePayload(
  testParams: Partial<CopilotMetricsInsightsPayload> = {},
): CopilotMetricsInsightsPayload {
  return Object.assign(
    {
      historicalMetrics: {
        data: [
          {
            id: '1',
            label: 'Week 52',
            shortLabel: 'W52',
            startDate: '2022-12-29',
            endDate: '2023-01-04',
            total: 100,
            active: 80,
            inactive: 10,
            dormant: 10,
          },
          {
            id: '2',
            label: 'Week 1',
            shortLabel: 'W1',
            startDate: '2023-01-05',
            endDate: '2023-01-11',
            total: 100,
            active: 80,
            inactive: 10,
            dormant: 10,
          },
          {
            id: '3',
            label: 'Week 2',
            shortLabel: 'W2',
            startDate: '2023-01-12',
            endDate: '2023-01-18',
            total: 100,
            active: 80,
            inactive: 10,
            dormant: 10,
          },
          {
            id: '4',
            label: 'Week 3',
            shortLabel: 'W3',
            startDate: '2023-01-19',
            endDate: '2023-01-25',
            total: 100,
            active: 80,
            inactive: 10,
            dormant: 10,
          },
          {
            id: '5',
            label: 'Week 4',
            shortLabel: 'W4',
            startDate: '2023-01-26',
            endDate: '2023-02-01',
            total: 100,
            active: 80,
            inactive: 10,
            dormant: 10,
          },
          {
            id: '6',
            label: 'Week 5',
            shortLabel: 'W5',
            startDate: '2023-02-02',
            endDate: '2023-02-08',
            total: 100,
            active: 80,
            inactive: 10,
            dormant: 10,
          },
          {
            id: '7',
            label: 'Week 6',
            shortLabel: 'W6',
            startDate: '2023-02-09',
            endDate: '2023-02-15',
            total: 100,
            active: 80,
            inactive: 10,
            dormant: 10,
          },
        ],
        overallStartDate: '2022-12-29',
        overallEndDate: '2024-01-04',
      },
      csvDownloadUrl: 'https://example.com/csv-download-url',
      csvFilename: 'copilot-user-onboarding-report',
      copilotSeatManagementLink: 'copilot-seat-management-link',
      dialogInfo: {
        text: 'This text is shown in the dialog body.',
        helpLinks: [
          {
            text: 'Learn more about Copilot text 1',
            url: 'https://example.com/learn-about-copilot-1',
          },
          {
            text: 'Learn more about Copilot text 2',
            url: 'https://example.com/learn-about-copilot-2',
          },
        ],
      },
      inviteMembersLink: 'invite-members-link',
      metricsDataType: CopilotMetricsDataType.Adoption,
      metricsInsightsUrl: 'https://example.com/metrics-insights-url',
      metricsTitle: 'Copilot user onboarding',
      showCopilotMetricsCatalog: true,
    },
    testParams,
  )
}

export function getCompletionsAcceptanceRateRoutePayload(
  testParams: Partial<CopilotMetricsInsightsPayload> = {},
): CopilotMetricsInsightsPayload {
  return Object.assign(
    {
      historicalMetrics: {
        data: [
          {
            id: '1',
            label: 'Week 52',
            shortLabel: 'W52',
            startDate: '2022-12-29',
            endDate: '2023-01-04',
            lowEngagement: {
              total: 100,
              accepted: 80,
              acceptanceRate: 0.8,
            },
            moderateEngagement: {
              total: 50,
              accepted: 25,
              acceptanceRate: 0.5,
            },
            highEngagement: {
              total: 20,
              accepted: 5,
              acceptanceRate: 0.25,
            },
          },
          {
            id: '2',
            label: 'Week 1',
            shortLabel: 'W1',
            startDate: '2023-01-05',
            endDate: '2023-01-11',
            lowEngagement: {
              total: 100,
              accepted: 80,
              acceptanceRate: 0.8,
            },
            moderateEngagement: {
              total: 50,
              accepted: 25,
              acceptanceRate: 0.5,
            },
            highEngagement: {
              total: 20,
              accepted: 5,
              acceptanceRate: 0.25,
            },
          },
          {
            id: '3',
            label: 'Week 2',
            shortLabel: 'W2',
            startDate: '2023-01-12',
            endDate: '2023-01-18',
            lowEngagement: {
              total: 100,
              accepted: 80,
              acceptanceRate: 0.8,
            },
            moderateEngagement: {
              total: 50,
              accepted: 25,
              acceptanceRate: 0.5,
            },
            highEngagement: {
              total: 20,
              accepted: 5,
              acceptanceRate: 0.25,
            },
          },
        ],
        overallStartDate: '2022-12-29',
        overallEndDate: '2023-01-18',
      },
      csvDownloadUrl: 'https://example.com/csv-download-url',
      csvFilename: 'copilot-user-completions-acceptance-rate-report',
      copilotSeatManagementLink: 'copilot-seat-management-link',
      dialogInfo: {
        text: 'This text is shown in the dialog body.',
        helpLinks: [
          {
            text: 'Learn more about Copilot text 1',
            url: 'https://example.com/learn-about-copilot-1',
          },
          {
            text: 'Learn more about Copilot text 2',
            url: 'https://example.com/learn-about-copilot-2',
          },
        ],
      },
      inviteMembersLink: 'invite-members-link',
      metricsDataType: CopilotMetricsDataType.CodeAcceptance,
      metricsInsightsUrl: 'https://example.com/metrics-insights-url',
      metricsTitle: 'Copilot code completions acceptance rate',
      showCopilotMetricsCatalog: true,
    },
    testParams,
  )
}

export function getGeneratedCodeAcceptanceRateRoutePayload(
  testParams: Partial<CopilotMetricsInsightsPayload> = {},
): CopilotMetricsInsightsPayload {
  return Object.assign(
    {
      historicalMetrics: {
        data: [
          {
            id: '1',
            label: 'Week 52',
            shortLabel: 'W52',
            startDate: '2022-12-29',
            endDate: '2023-01-04',
            lowEngagement: {
              total: 100,
              accepted: 80,
              acceptanceRate: 0.8,
            },
            moderateEngagement: {
              total: 50,
              accepted: 25,
              acceptanceRate: 0.5,
            },
            highEngagement: {
              total: 20,
              accepted: 5,
              acceptanceRate: 0.25,
            },
          },
          {
            id: '2',
            label: 'Week 1',
            shortLabel: 'W1',
            startDate: '2023-01-05',
            endDate: '2023-01-11',
            lowEngagement: {
              total: 100,
              accepted: 80,
              acceptanceRate: 0.8,
            },
            moderateEngagement: {
              total: 50,
              accepted: 25,
              acceptanceRate: 0.5,
            },
            highEngagement: {
              total: 20,
              accepted: 5,
              acceptanceRate: 0.25,
            },
          },
          {
            id: '3',
            label: 'Week 2',
            shortLabel: 'W2',
            startDate: '2023-01-12',
            endDate: '2023-01-18',
            lowEngagement: {
              total: 100,
              accepted: 80,
              acceptanceRate: 0.8,
            },
            moderateEngagement: {
              total: 50,
              accepted: 25,
              acceptanceRate: 0.5,
            },
            highEngagement: {
              total: 20,
              accepted: 5,
              acceptanceRate: 0.25,
            },
          },
        ],
        overallStartDate: '2022-12-29',
        overallEndDate: '2023-01-18',
      },
      copilotSeatManagementLink: 'copilot-seat-management-link',
      csvDownloadUrl: 'https://example.com/csv-download-url',
      csvFilename: 'copilot-generated-code-acceptance-rate-report',
      dialogInfo: {
        text: 'This text is shown in the dialog body.',
        helpLinks: [
          {
            text: 'Learn more about Copilot text 1',
            url: 'https://example.com/learn-about-copilot-1',
          },
          {
            text: 'Learn more about Copilot text 2',
            url: 'https://example.com/learn-about-copilot-2',
          },
        ],
      },
      inviteMembersLink: 'invite-members-link',
      metricsDataType: CopilotMetricsDataType.CodeAcceptance,
      metricsInsightsUrl: 'https://example.com/metrics-insights-url',
      metricsTitle: 'Copilot generated code acceptance rate',
      showCopilotMetricsCatalog: true,
    },
    testParams,
  )
}

export function getAverageContributionRoutePayload(
  testParams: Partial<CopilotMetricsInsightsPayload> = {},
): CopilotMetricsInsightsPayload {
  return Object.assign(
    {
      historicalMetrics: {
        data: [
          {
            id: '1',
            label: 'Week 52',
            shortLabel: 'W52',
            startDate: '2022-12-29',
            endDate: '2023-01-04',
            noCopilot: {
              average: 15.2,
              percentDifference: 0,
            },
            lowEngagement: {
              average: 18.5,
              percentDifference: 21.7,
            },
            moderateEngagement: {
              average: 22.1,
              percentDifference: 45.4,
            },
            highEngagement: {
              average: 28.3,
              percentDifference: 86.2,
            },
          },
          {
            id: '2',
            label: 'Week 1',
            shortLabel: 'W1',
            startDate: '2023-01-05',
            endDate: '2023-01-11',
            noCopilot: {
              average: 16.1,
              percentDifference: 0,
            },
            lowEngagement: {
              average: 19.2,
              percentDifference: 19.3,
            },
            moderateEngagement: {
              average: 23.7,
              percentDifference: 47.2,
            },
            highEngagement: {
              average: 29.8,
              percentDifference: 85.1,
            },
          },
          {
            id: '3',
            label: 'Week 2',
            shortLabel: 'W2',
            startDate: '2023-01-12',
            endDate: '2023-01-18',
            noCopilot: {
              average: 14.8,
              percentDifference: 0,
            },
            lowEngagement: {
              average: 17.9,
              percentDifference: 20.9,
            },
            moderateEngagement: {
              average: 21.5,
              percentDifference: 45.3,
            },
            highEngagement: {
              average: 27.1,
              percentDifference: 83.1,
            },
          },
        ],
        overallStartDate: '2022-12-29',
        overallEndDate: '2023-01-18',
      },
      csvDownloadUrl: 'https://example.com/csv-download-url',
      csvFilename: 'copilot-average-contribution-report',
      copilotSeatManagementLink: 'copilot-seat-management-link',
      dialogInfo: {
        text: 'This text is shown in the dialog body.',
        helpLinks: [
          {
            text: 'Learn more about Copilot text 1',
            url: 'https://example.com/learn-about-copilot-1',
          },
          {
            text: 'Learn more about Copilot text 2',
            url: 'https://example.com/learn-about-copilot-2',
          },
        ],
      },
      inviteMembersLink: 'invite-members-link',
      metricsDataType: CopilotMetricsDataType.AverageContribution,
      metricsInsightsUrl: 'https://example.com/metrics-insights-url',
      metricsTitle: 'Copilot average contribution metrics',
      showCopilotMetricsCatalog: true,
    },
    testParams,
  )
}
export function getAveragePullRequestLeadTimeRoutePayload(
  testParams: Partial<CopilotMetricsInsightsPayload> = {},
): CopilotMetricsInsightsPayload {
  return Object.assign(
    {
      historicalMetrics: {
        data: [
          {
            id: '1',
            label: 'Week 52',
            shortLabel: 'W52',
            startDate: '2022-12-29',
            endDate: '2023-01-04',
            noCopilot: {
              average: 72,
              percentDifference: 0,
            },
            lowEngagement: {
              average: 65,
              percentDifference: -9.2,
            },
            moderateEngagement: {
              average: 58,
              percentDifference: -19.6,
            },
            highEngagement: {
              average: 45,
              percentDifference: -37.8,
            },
          },
          {
            id: '2',
            label: 'Week 1',
            shortLabel: 'W1',
            startDate: '2023-01-05',
            endDate: '2023-01-11',
            noCopilot: {
              average: 68,
              percentDifference: 0,
            },
            lowEngagement: {
              average: 61,
              percentDifference: -9.8,
            },
            moderateEngagement: {
              average: 54,
              percentDifference: -19.5,
            },
            highEngagement: {
              average: 42,
              percentDifference: -38.0,
            },
          },
          {
            id: '3',
            label: 'Week 2',
            shortLabel: 'W2',
            startDate: '2023-01-12',
            endDate: '2023-01-18',
            noCopilot: {
              average: 75,
              percentDifference: 0,
            },
            lowEngagement: {
              average: 68,
              percentDifference: -8.9,
            },
            moderateEngagement: {
              average: 60,
              percentDifference: -19.2,
            },
            highEngagement: {
              average: 47,
              percentDifference: -36.4,
            },
          },
        ],
        overallStartDate: '2022-12-29',
        overallEndDate: '2023-01-18',
      },
      csvDownloadUrl: 'https://example.com/csv-download-url',
      csvFilename: 'copilot-average-pull-request-lead-time-report',
      copilotSeatManagementLink: 'copilot-seat-management-link',
      dialogInfo: {
        text: 'This text is shown in the dialog body.',
        helpLinks: [
          {
            text: 'Learn more about Copilot text 1',
            url: 'https://example.com/learn-about-copilot-1',
          },
          {
            text: 'Learn more about Copilot text 2',
            url: 'https://example.com/learn-about-copilot-2',
          },
        ],
      },
      inviteMembersLink: 'invite-members-link',
      metricsDataType: CopilotMetricsDataType.AveragePullRequestLeadTime,
      metricsInsightsUrl: 'https://example.com/metrics-insights-url',
      metricsTitle: 'Copilot average pull request lead time',
      showCopilotMetricsCatalog: true,
    },
    testParams,
  )
}
