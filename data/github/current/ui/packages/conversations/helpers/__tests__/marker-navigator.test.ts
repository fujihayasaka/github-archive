import type {DiffAnnotation, ThreadSummary} from '../../types'
import type {GenericMarkerNavEl} from '../marker-navigator'
import {MarkerNavigator} from '../marker-navigator'

describe('MarkerNavigator', () => {
  const mockThreads: Array<ThreadSummary | GenericMarkerNavEl | DiffAnnotation> = [
    {
      id: '1',
      author: {
        avatarUrl: 'https://avatars.githubusercontent.com/u/12345',
        login: 'monalisa',
      },
    },
    {
      id: '2',
      author: {
        avatarUrl: 'https://avatars.githubusercontent.com/u/12345',
        login: 'monalisa',
      },
    } as ThreadSummary,
    {
      id: '3',
      author: {
        avatarUrl: 'https://avatars.githubusercontent.com/u/12345',
        login: 'monalisa',
      },
    } as ThreadSummary,
  ]

  const mockDiffAnnotation = {
    id: '4',
    databaseId: 4,
    annotationLevel: 'WARNING',
  } as DiffAnnotation

  // Setup and teardown DOM for testing
  beforeEach(() => {
    // Set up test DOM structure
    document.body.innerHTML = `
      <div id="container">
        <div data-marker-id="1">
          <div data-marker-navigation-comment-id="1-1" data-marker-navigation-comment-thread-id="1"></div>
          <div data-marker-navigation-comment-id="1-2" data-marker-navigation-comment-thread-id="1"></div>
        </div>
        <div data-marker-id="2">
          <div data-marker-navigation-comment-id="2-1" data-marker-navigation-comment-thread-id="2"></div>
          <div data-marker-navigation-comment-id="2-2" data-marker-navigation-comment-thread-id="2"></div>
          <div data-marker-navigation-comment-id="2-3" data-marker-navigation-comment-thread-id="2"></div>
        </div>
        <div data-marker-id="3">
          <!-- No comments -->
        </div>
        <div data-marker-id="4">
          <!-- Annotation marker -->
        </div>
      </div>
    `
  })

  afterEach(() => {
    document.body.innerHTML = ''
  })

  // Helper functions to get DOM elements
  function getMarkerElement(markerId: string): Element | null {
    return document.querySelector(`[data-marker-id="${markerId}"]`)
  }

  function getCommentElement(markerId: string, commentId: string): Element | null {
    return document.querySelector(`[data-marker-id="${markerId}"] [data-marker-navigation-comment-id="${commentId}"]`)
  }

  describe('constructor', () => {
    it('should initialize with markers', () => {
      const navigator = new MarkerNavigator(mockThreads)
      expect(navigator['markers'].length).toBe(3)
    })

    it('should convert databaseId to string id if present', () => {
      const navigator = new MarkerNavigator([mockDiffAnnotation])
      expect(navigator['markers'][0]!.id).toBe('4')
    })

    it('should initialize with current marker position if id is provided', () => {
      const navigator = new MarkerNavigator(mockThreads, '2')
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '2',
        index: 1,
      })
    })

    it('should initialize marker comments from the DOM', () => {
      const navigator = new MarkerNavigator(mockThreads)
      expect(navigator['markerComments']?.['1']?.length).toBe(2)
      expect(navigator['markerComments']?.['2']?.length).toBe(3)
    })
  })

  describe('focusMarker', () => {
    it('should set current marker position when marker id exists', () => {
      const navigator = new MarkerNavigator(mockThreads)
      navigator.focusMarker('2')
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '2',
        index: 1,
      })
    })

    it('should not change current marker position when marker id does not exist', () => {
      const navigator = new MarkerNavigator(mockThreads, '1')
      navigator.focusMarker('999')
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '1',
        index: 0,
      })
    })
  })

  describe('focusedMarker', () => {
    it('should return the currently focused marker', () => {
      const navigator = new MarkerNavigator(mockThreads, '2')
      expect(navigator.focusedMarker).toEqual(mockThreads[1])
    })

    it('should return undefined when no marker is focused', () => {
      const navigator = new MarkerNavigator(mockThreads)
      expect(navigator.focusedMarker).toBeUndefined()
    })
  })

  describe('moveToNextMarker', () => {
    it('should return undefined for empty markers', () => {
      const navigator = new MarkerNavigator([])
      expect(navigator.moveToNextMarker('ArrowDown', undefined)).toBeUndefined()
    })

    it('should move to first marker when no marker is focused and direction is ArrowDown', () => {
      const navigator = new MarkerNavigator(mockThreads)
      const nextMarker = navigator.moveToNextMarker('ArrowDown', undefined)
      expect(nextMarker).toEqual(mockThreads[0])
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '1',
        index: 0,
      })
    })

    it('should move to last marker when no marker is focused and direction is ArrowUp', () => {
      const navigator = new MarkerNavigator(mockThreads)
      const nextMarker = navigator.moveToNextMarker('ArrowUp', undefined)
      expect(nextMarker).toEqual(mockThreads[2])
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '3',
        index: 2,
      })
    })

    it('should move to next marker when current marker is not the last one', () => {
      const navigator = new MarkerNavigator(mockThreads, '1')
      const markerEl = getMarkerElement('1')
      const nextMarker = navigator.moveToNextMarker('ArrowDown', markerEl as Element)
      expect(nextMarker).toEqual(mockThreads[1])
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '2',
        index: 1,
      })
    })

    it('should move to previous marker when current marker is not the first one', () => {
      const navigator = new MarkerNavigator(mockThreads, '2')
      const markerEl = getMarkerElement('2') as Element
      const nextMarker = navigator.moveToNextMarker('ArrowUp', markerEl)
      expect(nextMarker).toEqual(mockThreads[0])
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '1',
        index: 0,
      })
    })

    it('should return undefined when at the last marker and moving down', () => {
      const navigator = new MarkerNavigator(mockThreads, '3')
      const markerEl = getMarkerElement('3') as Element
      const nextMarker = navigator.moveToNextMarker('ArrowDown', markerEl)
      expect(nextMarker).toBeUndefined()
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '3',
        index: 2,
      })
    })

    it('should return undefined when at the first marker and moving up', () => {
      const navigator = new MarkerNavigator(mockThreads, '1')
      const markerEl = getMarkerElement('1') as Element
      const nextMarker = navigator.moveToNextMarker('ArrowUp', markerEl)
      expect(nextMarker).toBeUndefined()
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '1',
        index: 0,
      })
    })

    it('should update current marker position from the DOM element', () => {
      const navigator = new MarkerNavigator(mockThreads)
      const markerEl = getMarkerElement('2') as Element
      navigator.moveToNextMarker('ArrowDown', markerEl)
      expect(navigator['currentMarkerPosition']).toEqual({
        markerId: '3',
        index: 2,
      })
    })
  })

  describe('moveToNextMarkerItem', () => {
    it('should return undefined when no element is provided', () => {
      const navigator = new MarkerNavigator(mockThreads)
      expect(navigator.moveToNextMarkerItem('ArrowDown', undefined)).toBeUndefined()
    })

    it('should return undefined when no marker comments are found', () => {
      const navigator = new MarkerNavigator(mockThreads)
      navigator['markerComments'] = null
      const commentEl = getCommentElement('1', '1-1')
      expect(navigator.moveToNextMarkerItem('ArrowDown', commentEl as Element)).toBeUndefined()
    })

    it('should return undefined when the marker has no comments', () => {
      const navigator = new MarkerNavigator(mockThreads)
      navigator['markerComments'] = {'3': []}
      // Create a fake comment element for marker 3 since it doesn't exist in DOM
      const commentEl = document.createElement('div')
      commentEl.setAttribute('data-marker-id', '3')
      commentEl.setAttribute('data-marker-navigation-comment-id', '3-1')
      expect(navigator.moveToNextMarkerItem('ArrowDown', commentEl)).toBeUndefined()
    })

    it('should move to the next comment in the marker', () => {
      const navigator = new MarkerNavigator(mockThreads)
      const commentEl = getCommentElement('2', '2-1') as Element
      const nextComment = navigator.moveToNextMarkerItem('ArrowDown', commentEl)
      expect(nextComment).toEqual({id: '2-2'})
      expect(navigator['currentMarkerCommentPosition']).toEqual({
        markerId: '2-2',
        index: 1,
      })
    })

    it('should move to the previous comment in the marker', () => {
      const navigator = new MarkerNavigator(mockThreads)
      const commentEl = getCommentElement('2', '2-2') as Element
      const prevComment = navigator.moveToNextMarkerItem('ArrowUp', commentEl)
      expect(prevComment).toEqual({id: '2-1'})
      expect(navigator['currentMarkerCommentPosition']).toEqual({
        markerId: '2-1',
        index: 0,
      })
    })

    it('should return undefined when at the first comment and moving up', () => {
      const navigator = new MarkerNavigator(mockThreads)
      const commentEl = getCommentElement('2', '2-1') as Element
      expect(navigator.moveToNextMarkerItem('ArrowUp', commentEl)).toBeUndefined()
    })

    it('should return undefined when at the last comment and moving down', () => {
      const navigator = new MarkerNavigator(mockThreads)
      const commentEl = getCommentElement('2', '2-3') as Element
      expect(navigator.moveToNextMarkerItem('ArrowDown', commentEl)).toBeUndefined()
    })
  })
})
