import {mockModel} from '../../../test-utils/mock-data'
import {buildEvalsConfig} from '../evals-config'
import type {Config, DataRow, EvaluatorCfg} from '../evals-sdk/config'
import {findModel} from '../models'
import type {PromptConfig} from '../prompts'

jest.mock('../models', () => ({
  findModel: jest.fn(),
}))

describe('buildEvalsConfig', () => {
  it('should build the evals config correctly', () => {
    const mockModel1 = mockModel({id: 'model1', capabilities: {systemPrompt: true}})
    const mockModel2 = mockModel({id: 'model2', capabilities: {systemPrompt: false}})
    const mockModels = [mockModel1, mockModel2]
    ;(findModel as jest.Mock).mockImplementation((id: string) => mockModels.find(model => model.id === id))
    const currentTimestamp = new Date()

    const prompts: PromptConfig[] = [
      {
        model: 'model1',
        modelParameters: {param1: 'value1'},
        messages: [
          {role: 'system', message: 'System message', timestamp: currentTimestamp},
          {role: 'user', message: 'User message', timestamp: currentTimestamp},
        ],
      },
      {
        model: 'model2',
        modelParameters: {param2: 'value2'},
        messages: [
          {role: 'system', message: 'System message', timestamp: currentTimestamp},
          {role: 'user', message: 'User message', timestamp: currentTimestamp},
        ],
      },
    ]

    const rows: DataRow[] = [{id: 'row1'}]
    const evaluators: EvaluatorCfg[] = [{name: 'evaluator1'}]

    const expectedConfig: Config = {
      prompts: [
        {
          id: 0,
          model: {
            id: 'model1',
            parameters: {param1: 'value1'},
          },
          messages: [
            {role: 'system', message: 'System message', timestamp: currentTimestamp},
            {role: 'user', message: 'User message', timestamp: currentTimestamp},
          ],
        },
        {
          id: 1,
          model: {
            id: 'model2',
            parameters: {param2: 'value2'},
          },
          messages: [{role: 'user', message: 'User message', timestamp: currentTimestamp}],
        },
      ],
      datasets: [
        {
          rows,
        },
      ],
      evaluators,
    }

    const result = buildEvalsConfig(prompts, rows, evaluators, mockModels)
    expect(result).toEqual(expectedConfig)
  })
})
