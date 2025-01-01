import type {DetectionViewProps} from '../components/DetectionView'
import type {PreventionViewProps} from '../components/PreventionView'
import type {RemediationViewProps} from '../components/RemediationView'
import type {SecurityCenterOverviewDashboardProps} from '../SecurityCenterOverviewDashboard'

export function getSecurityCenterOverviewDashboardProps(): SecurityCenterOverviewDashboardProps {
  return {
    initialQuery: '',
    initialDateSpan: {period: 'last30days'},
    feedbackLink: {
      text: 'Give feedback',
      url: '#',
    },
    visibleSecurityFeatures: ['code-scanning', 'dependabot', 'secret-scanning'],
    customProperties: [],
    filterProviders: [],
    showCsvExport: true,
  }
}

export function getDetectionViewProps(): DetectionViewProps {
  return {
    submittedQuery: '',
    startDateString: '2024-08-10',
    endDateString: '2024-08-16',
    selectedDateSpan: {period: 'last30days'},
    customProperties: [],
    initialSelectedImpactAnalysisTable: 'repositories',
  }
}

export function getRemediationViewProps(): RemediationViewProps {
  return {
    submittedQuery: '',
    startDateString: '2024-08-10',
    endDateString: '2024-08-16',
    allowAutofixFeatures: false,
  }
}

export function getPreventionViewProps(): PreventionViewProps {
  return {
    submittedQuery: '',
    startDateString: '2024-08-10',
    endDateString: '2024-08-16',
    customProperties: [],
    selectedDateSpan: {period: 'last30days'},
  }
}
