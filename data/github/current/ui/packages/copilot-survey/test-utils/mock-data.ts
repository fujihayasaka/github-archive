import type {CopilotSurveyProps} from '../CopilotSurvey'

export function getCopilotSurveyProps(): CopilotSurveyProps {
  return {
    surveyLink: 'https://github.surveymonkey.com/r/LPCZZCK?uid=monalisa',
    surveyOpenCallbackPath: 'http://github.localhost/github/internal-server/copilot/feedback-survey/open',
    surveyDismissCallbackPath: 'http://github.localhost/github/internal-server/copilot/feedback_survey#dismiss',
  }
}
