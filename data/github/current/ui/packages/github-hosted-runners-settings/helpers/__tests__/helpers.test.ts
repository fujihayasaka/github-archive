import {curatedImagesSortFn, isCanaryCuratedImage, isLatestCuratedImage} from '../helpers'
import type {Image} from '../../types/image'

describe('isLatestVersion', () => {
  test.each([
    {imageName: 'hello world', expectedOutput: false},
    {imageName: 'Test - Nvidia GPU image', expectedOutput: false},
    {imageName: 'Ubuntu 18.04', expectedOutput: false},
    {imageName: 'Ubuntu Latest long name', expectedOutput: false},
    {imageName: 'Ubuntu Latest', expectedOutput: true},
    {imageName: 'Ubuntu Latest (18.04)', expectedOutput: true},
    {imageName: 'Windows Server 2015', expectedOutput: false},
    {imageName: 'Windows Latest (2015)', expectedOutput: true},
  ])('%s', ({imageName, expectedOutput}) => {
    expect(isLatestCuratedImage(imageName)).toEqual(expectedOutput)
  })
})

describe('isCanaryCuratedImage', () => {
  test.each([
    {imageName: 'hello world', expectedOutput: false},
    {imageName: 'Test - Nvidia GPU image', expectedOutput: false},
    {imageName: 'Ubuntu 18.04', expectedOutput: false},
    {imageName: 'Ubuntu 18.04 - Canary', expectedOutput: true},
  ])('%s', ({imageName, expectedOutput}) => {
    expect(isCanaryCuratedImage(imageName)).toEqual(expectedOutput)
  })
})

describe('curatedImagesSortFn', () => {
  const createImagesList = (imageNames: string[]): Image[] => {
    return imageNames.map(x => {
      return {displayName: x} as Image
    })
  }

  test('simple case', () => {
    const input = createImagesList(['Test - Nvidia GPU image', 'Codespaces Prebuild', 'Ubuntu 20.04', 'Ubuntu 18.04'])
    const output = createImagesList(['Codespaces Prebuild', 'Test - Nvidia GPU image', 'Ubuntu 18.04', 'Ubuntu 20.04'])

    expect(input.sort(curatedImagesSortFn)).toEqual(output)
  })

  test('with latest images', () => {
    const input = createImagesList([
      'Test - Nvidia GPU image',
      'Codespaces Prebuild',
      'Ubuntu 20.04',
      'Ubuntu Latest (18.04)',
      'Ubuntu 18.04',
    ])
    const output = createImagesList([
      'Ubuntu Latest (18.04)',
      'Codespaces Prebuild',
      'Test - Nvidia GPU image',
      'Ubuntu 18.04',
      'Ubuntu 20.04',
    ])

    expect(input.sort(curatedImagesSortFn)).toEqual(output)
  })

  test('with canary images', () => {
    const input = createImagesList([
      'Test - Nvidia GPU image',
      'Codespaces Prebuild',
      'Ubuntu 20.04',
      'Ubuntu Latest (18.04)',
      'Ubuntu 18.04 - Canary',
      'Ubuntu 20.04 - Canary',
      'Ubuntu 18.04',
    ])
    const output = createImagesList([
      'Ubuntu Latest (18.04)',
      'Codespaces Prebuild',
      'Test - Nvidia GPU image',
      'Ubuntu 18.04',
      'Ubuntu 20.04',
      'Ubuntu 18.04 - Canary',
      'Ubuntu 20.04 - Canary',
    ])

    expect(input.sort(curatedImagesSortFn)).toEqual(output)
  })
})
