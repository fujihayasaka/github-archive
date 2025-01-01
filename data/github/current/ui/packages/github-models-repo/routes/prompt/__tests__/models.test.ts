import {mockModel} from '../../../test-utils/mock-data'
import {findModel, promptModelIdentifierFor} from '../models'

const model1 = mockModel()
const model2 = mockModel({
  id: 'azureml://registries/azure-openai/models/model_2/versions/2024-11-20',
  original_name: 'model_2',
  name: 'Model2',
  friendly_name: 'Model 2',
})
const model3 = mockModel({
  id: 'azureml://registries/azure-cohere/models/Model3/versions/2024-11-20',
  original_name: 'Model3',
  name: 'model_three',
  friendly_name: 'Model 3',
  publisher: 'Cohere',
  publisherSlug: 'cohere',
})
const model4 = mockModel({
  id: 'azureml://registries/azure-meta/models/Model-4/versions/2024-11-20',
  original_name: 'Model-4',
  name: 'fourthmodel',
  friendly_name: 'Model 4',
  publisher: 'Meta',
  publisherSlug: 'meta',
})
const models = [model1, model2, model3, model4]

describe('models', () => {
  describe('findModel', () => {
    it('finds a model by its original name, case insensitive', () => {
      expect(findModel(model1.original_name.toUpperCase(), models)).toEqual(model1)
    })

    it('finds a model by its name, case insensitive', () => {
      expect(findModel(model2.name.toUpperCase(), models)).toEqual(model2)
    })

    it('finds a model by its publisher slug and model name, case insensitive', () => {
      expect(findModel(`${model3.publisherSlug}/${model3.name}`.toUpperCase(), models)).toEqual(model3)
    })

    it('finds a model by its publisher name and model name, case insensitive', () => {
      expect(findModel(`${model4.publisher}/${model4.name}`.toUpperCase(), models)).toEqual(model4)
    })

    it('finds a model by ID', () => {
      expect(findModel(model3.id, models)).toEqual(model3)
    })

    it('finds a model by its prompt file identifier', () => {
      expect(findModel(promptModelIdentifierFor(model1), models)).toEqual(model1)
    })
  })
})
