import {reposPickerDefinitionsPath, reposPickerRepositoriesPath} from '../paths'

describe('reposPickerDefinitionsPath', () => {
  it('should return the correct path for a repo query', () => {
    expect(reposPickerDefinitionsPath({orgLogin: 'acme'})).toEqual(`/repos-picker/definitions?org=acme`)
  })

  it('should return the correct path when enconding', () => {
    expect(reposPickerDefinitionsPath({orgLogin: '你好你'})).toEqual(
      `/repos-picker/definitions?org=%E4%BD%A0%E5%A5%BD%E4%BD%A0`,
    )
  })
})

describe('reposPickerRepositoriesPath', () => {
  it('should return the correct path for no orgLogin neither query', () => {
    expect(reposPickerRepositoriesPath({})).toEqual(`/repos-picker/repositories`)
  })

  it('should return the correct path for when no query', () => {
    expect(reposPickerRepositoriesPath({orgLogin: 'acme'})).toEqual(`/repos-picker/repositories?org=acme`)
  })

  it('should return the correct path for empty query', () => {
    expect(reposPickerRepositoriesPath({orgLogin: 'acme', query: ''})).toEqual(`/repos-picker/repositories?org=acme`)
  })

  it('should return the correct path for no orgLogin', () => {
    expect(reposPickerRepositoriesPath({query: 'foo'})).toEqual(`/repos-picker/repositories?q=foo`)
  })

  it('should return the correct path for a repo query', () => {
    expect(reposPickerRepositoriesPath({orgLogin: 'acme', query: 'foo'})).toEqual(
      `/repos-picker/repositories?org=acme&q=foo`,
    )
  })

  it('should return the correct path when enconding', () => {
    expect(reposPickerRepositoriesPath({orgLogin: '你好你', query: 'foo'})).toEqual(
      `/repos-picker/repositories?org=%E4%BD%A0%E5%A5%BD%E4%BD%A0&q=foo`,
    )
  })
})
