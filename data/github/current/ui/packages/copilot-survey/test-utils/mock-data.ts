import type {CopilotSurveyProps} from '../CopilotSurvey'

export function getCopilotSurveyProps(): CopilotSurveyProps {
  return {
    bannerTitle: 'Take our Copilot survey',
    bannerText: 'We want to hear your feedback on Copilot',
    bannerSlug: 'copilot-survey',
    ctaUrl: 'https://github.surveymonkey.com/r/LPCZZCK?uid=monalisa',
    ctaText: 'Take the survey',
    surveyOpenCallbackPath: 'http://github.localhost/github/internal-server/copilot/feedback-survey/open',
    surveyDismissCallbackPath: 'http://github.localhost/github/internal-server/copilot/feedback_survey#dismiss',
  }
}
