import {ModelUrlHelper} from '../model-url-helper'
import {mockModel as model} from '../../routes/playground/__tests__/mocks'

describe('modelUrlFromModel', () => {
  it('returns the model url for a model', () => {
    expect(ModelUrlHelper.modelUrl(model)).toEqual(`/marketplace/models/${model.registry}/${model.name}`)
  })

  it('returns the playground url for a model', () => {
    expect(ModelUrlHelper.playgroundUrl(model)).toEqual(
      `/marketplace/models/${model.registry}/${model.name}/playground`,
    )
  })
})
