import type {DiffAnnotation} from '@github-ui/conversations'
import {DiffAnnotationLevels} from '@github-ui/conversations'

import {groupAnnotationsByPath} from '../annotation-helpers'

/**
 * Stubbed annotation query response that includes:
 *   - 2 valid annotations on changed files (1 failure, 1 warning)
 *   - 1 valid annotation on unchanged file (1 notice)
 */
const annotations: DiffAnnotation[] = [
  {
    id: 'annotation-1',
    databaseId: 123456,
    annotationLevel: DiffAnnotationLevels.Failure,
    checkRun: {
      detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/1',
      name: 'github-all-features',
    },
    appAvatarUrl: '/identicons/app/app/checks-buddy',
    appAvatarAltText: 'Checks Buddy avatar image',
    checkSuiteName: 'Namfix',
    endLine: 3,
    startLine: 2,
    message: 'This might be problematic in the future because X.',
    path: 'contributing.md',
    pathDigest: '0b82d9a8fc9c94f7729e7685fca44dd89a479746f7cb14171e6dcdc7beb94387',
    title: 'AuthorizationContext#test_object_has_appropriate_scope',
  },
  {
    id: 'annotation-2',
    databaseId: 123457,
    annotationLevel: DiffAnnotationLevels.Warning,
    appAvatarUrl: '/identicons/app/app/checks-buddy',
    appAvatarAltText: 'Checks Buddy avatar image',
    checkSuiteName: 'Namfix',
    checkRun: {
      detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/1',
      name: 'github-all-features',
    },
    endLine: 1,
    startLine: 1,
    message: 'This might be problematic in the future because X.',
    path: 'evergreen.md',
    pathDigest: '5f1d74daafd8220ef02fadac02e113f9678fdd6fde0cf506a03bbcb667ad2235',
    title: 'MemberContext#test_does_not_include_member',
  },
  {
    id: 'annotation-3',
    databaseId: 123458,
    annotationLevel: DiffAnnotationLevels.Notice,
    checkRun: {
      detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/13',
      name: 'github-all-features',
    },
    appAvatarUrl: '/identicons/app/app/checks-buddy',
    appAvatarAltText: 'Checks Buddy avatar image',
    checkSuiteName: 'Namfix',
    endLine: 4,
    startLine: 1,
    message: 'This might be problematic in the future because X.',
    path: 'non-diff-annotation-file.md',
    pathDigest: '0ebcfa3266ee62da2424f0c76d3bfcdd38c632aa239f98795f2f574fe929645e',
    title: 'non-diff-annotation-file.md#L1-L2',
  },
]

describe('group annotations by path', () => {
  test('it returns a map of annotations grouped by path and start line', () => {
    const result = groupAnnotationsByPath(annotations)
    expect(result).toEqual({
      'contributing.md': {
        '3': [
          {
            id: 'annotation-1',
            databaseId: 123456,
            annotationLevel: 'FAILURE',
            checkRun: {
              detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/1',
              name: 'github-all-features',
            },
            appAvatarUrl: '/identicons/app/app/checks-buddy',
            appAvatarAltText: 'Checks Buddy avatar image',
            checkSuiteName: 'Namfix',
            endLine: 3,
            startLine: 2,
            message: 'This might be problematic in the future because X.',
            path: 'contributing.md',
            pathDigest: '0b82d9a8fc9c94f7729e7685fca44dd89a479746f7cb14171e6dcdc7beb94387',
            title: 'AuthorizationContext#test_object_has_appropriate_scope',
          },
        ],
      },
      'evergreen.md': {
        '1': [
          {
            id: 'annotation-2',
            databaseId: 123457,
            annotationLevel: 'WARNING',
            checkRun: {
              detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/1',
              name: 'github-all-features',
            },
            appAvatarUrl: '/identicons/app/app/checks-buddy',
            appAvatarAltText: 'Checks Buddy avatar image',
            checkSuiteName: 'Namfix',
            endLine: 1,
            startLine: 1,
            message: 'This might be problematic in the future because X.',
            path: 'evergreen.md',
            pathDigest: '5f1d74daafd8220ef02fadac02e113f9678fdd6fde0cf506a03bbcb667ad2235',
            title: 'MemberContext#test_does_not_include_member',
          },
        ],
      },
      'non-diff-annotation-file.md': {
        '4': [
          {
            id: 'annotation-3',
            databaseId: 123458,
            annotationLevel: 'NOTICE',
            checkRun: {
              detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/13',
              name: 'github-all-features',
            },
            appAvatarUrl: '/identicons/app/app/checks-buddy',
            appAvatarAltText: 'Checks Buddy avatar image',
            checkSuiteName: 'Namfix',
            endLine: 4,
            startLine: 1,
            message: 'This might be problematic in the future because X.',
            path: 'non-diff-annotation-file.md',
            pathDigest: '0ebcfa3266ee62da2424f0c76d3bfcdd38c632aa239f98795f2f574fe929645e',
            title: 'non-diff-annotation-file.md#L1-L2',
          },
        ],
      },
    })
  })
})
