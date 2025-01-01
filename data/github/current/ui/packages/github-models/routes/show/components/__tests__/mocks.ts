import type {SafeHTMLString} from '@github-ui/safe-html'
import type {ShowModelPayload} from '../../../../types'
import {ModelUrlHelper} from '../../../../utils/model-url-helper'
import {mockModel, mockModelInputSchema} from '../../../playground/__tests__/mocks'

export function mockShowModelPayload(overrides: Partial<ShowModelPayload> = {}): ShowModelPayload {
  const basePayload: ShowModelPayload = {
    model: mockModel,
    modelInputSchema: mockModelInputSchema,
    modelReadme: 'Sample readme content' as SafeHTMLString,
    modelLicense: mockModel.license as SafeHTMLString,
    readmeToc: [],
    modelTransparencyContent: 'Sample transparency content' as SafeHTMLString,
    playgroundUrl: ModelUrlHelper.playgroundUrl(mockModel),
    modelEvaluation: mockModel.evaluation as SafeHTMLString,
    canProvideAdditionalFeedback: false,
    isLoggedIn: true,
    canUseO1Models: true,
  }
  return {...basePayload, ...overrides}
}
