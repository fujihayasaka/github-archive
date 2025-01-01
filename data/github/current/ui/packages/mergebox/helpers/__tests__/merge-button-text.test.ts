import {mergeButtonText} from '../merge-button-text'
import {MergeMethod} from '../../types'

const defaultMergeButtonTextData = {
  mergeMethod: MergeMethod.MERGE,
  confirming: false,
  isBypassMerge: false,
  isAutoMergeAllowed: false,
}
describe('mergeButtonText', () => {
  test('it returns the correct text for Merge when bypass and auto merge are False', () => {
    expect('Merge pull request').toEqual(mergeButtonText(defaultMergeButtonTextData))
  })

  test('it returns the correct text for Merge when confirming and auto merge are true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      confirming: true,
      isAutoMergeAllowed: true,
    }
    expect('Confirm auto-merge').toEqual(mergeButtonText(data))
  })

  test('it returns the correct text for Merge when auto merge are true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      isAutoMergeAllowed: true,
    }
    expect('Enable auto-merge').toEqual(mergeButtonText(data))
  })
  test('it returns the correct text for Merge when bypass is true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      isBypassMerge: true,
    }
    expect('Bypass rules and merge').toEqual(mergeButtonText(data))
  })
  test('it returns the correct text for Squash when bypass and auto merge are False', () => {
    const data = {
      ...defaultMergeButtonTextData,
      mergeMethod: MergeMethod.SQUASH,
    }
    expect('Squash and merge').toEqual(mergeButtonText(data))
  })

  test('it returns the correct text for Squash when confirming and auto merge are true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      mergeMethod: MergeMethod.SQUASH,
      confirming: true,
      isAutoMergeAllowed: true,
    }
    expect('Confirm auto-merge (squash)').toEqual(mergeButtonText(data))
  })

  test('it returns the correct text for Squash when auto merge are true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      mergeMethod: MergeMethod.SQUASH,
      isAutoMergeAllowed: true,
    }
    expect('Enable auto-merge (squash)').toEqual(mergeButtonText(data))
  })
  test('it returns the correct text for Squash when bypass is true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      mergeMethod: MergeMethod.SQUASH,
      isBypassMerge: true,
    }
    expect('Bypass rules and merge (squash)').toEqual(mergeButtonText(data))
  })

  test('it returns the correct text for Rebase when bypass and auto merge are False', () => {
    const data = {
      ...defaultMergeButtonTextData,
      mergeMethod: MergeMethod.REBASE,
    }
    expect('Rebase and merge').toEqual(mergeButtonText(data))
  })

  test('it returns the correct text for Rebase when confirming and auto merge are true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      mergeMethod: MergeMethod.REBASE,
      confirming: true,
      isAutoMergeAllowed: true,
    }
    expect('Confirm auto-merge (rebase)').toEqual(mergeButtonText(data))
  })

  test('it returns the correct text for Rebase when auto merge are true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      mergeMethod: MergeMethod.REBASE,
      isAutoMergeAllowed: true,
    }
    expect('Enable auto-merge (rebase)').toEqual(mergeButtonText(data))
  })
  test('it returns the correct text for Rebase when bypass is true', () => {
    const data = {
      ...defaultMergeButtonTextData,
      mergeMethod: MergeMethod.REBASE,
      isBypassMerge: true,
    }
    expect('Bypass rules and merge (rebase)').toEqual(mergeButtonText(data))
  })
})
