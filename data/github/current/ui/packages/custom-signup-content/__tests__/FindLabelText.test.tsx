import {BLOCKS} from '@contentful/rich-text-types'
import {contentJSON} from './utils/mock-data'
import {FindLabelText} from '../helpers/find-label-text'
import type {ContentSchema} from '../lib/types/contentful/content-schema'

describe('FindLabelText', () => {
  it('returns the label text', () => {
    const result = FindLabelText(contentJSON)

    expect(result).toBe('Optional')
  })

  it('returns null if no signup-pill field', () => {
    const contentEntriesPayload: ContentSchema[] = []

    const result = FindLabelText(contentEntriesPayload)

    expect(result).toBeNull()
  })

  it('returns null if htmlId does not match', () => {
    const contentEntriesPayload: ContentSchema[] = [
      {
        sys: {
          id: '',
          contentType: {
            sys: {
              id: 'content',
            },
          },
        },
        fields: {
          title: '/signup Pill Optional',
          id: '',
          htmlId: 'somewrongtext',
          heading: 'Optional',
          text: {
            nodeType: BLOCKS.DOCUMENT,
            data: {},
            content: [],
          },
        },
      },
    ]

    const result = FindLabelText(contentEntriesPayload)

    expect(result).toBeNull()
  })
})
