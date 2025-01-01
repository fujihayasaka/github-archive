import {getSharedComponents} from '../utils'
import {MISSING_STORIES} from '../data/DO-NOT-ADD-TO-THIS-LIST-PLEASE--missing-stories'

const trimPath = (fullPath: string) => {
  return fullPath.slice(fullPath.indexOf('ui/packages/'))
}

describe('Shared components have stories', () => {
  const {paths, missingStoriesComponentPaths} = getSharedComponents()

  const missingStories: {[key: string]: boolean} = {}
  for (const componentFullPath of missingStoriesComponentPaths) {
    const componentPath = trimPath(componentFullPath)
    missingStories[componentPath] = true
  }

  const backfilled: string[] = []
  for (const componentPath of MISSING_STORIES) {
    if (missingStories[componentPath]) {
      missingStories[componentPath] = false
    } else {
      backfilled.push(componentPath)
    }
  }

  const trimmedComponentPaths = paths.map(componentPath => trimPath(componentPath))
  test.each(trimmedComponentPaths)(
    'Component `%s` must have a story file. Writing Storybook stories makes components discoverable, promotes reusability, and provides free accessibility (axe) scanning in CI!',
    componentPath => {
      expect(missingStories[componentPath]).toBeFalsy()
    },
  )

  test('Components with stories do not appear on the backfill list', () => {
    expect(backfilled).toEqual([])
  })
})
