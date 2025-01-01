import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {ScreenReaderManager} from '../screen-reader-manager'
import {announce} from '@github-ui/aria-live'

vi.mock('@github-ui/aria-live', () => ({
  announce: vi.fn(),
}))

describe('ScreenReaderManager Announcement', () => {
  describe('acceptSuggestion', () => {
    it('announces acceptance', () => {
      const screenReaderManager = new ScreenReaderManager(undefined, undefined, undefined)
      screenReaderManager.acceptSuggestion()
      expect(announce).toHaveBeenCalledWith('Suggestion accepted.')
    })
  })

  describe('announceCompletion', () => {
    let screenReaderManager: ScreenReaderManager
    beforeEach(() => {
      screenReaderManager = new ScreenReaderManager(undefined, undefined, undefined)
    })

    it('completion is less than 250 characters', () => {
      const completion =
        'This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text.'
      screenReaderManager.announceCompletion(completion)

      const expectedAnnouncement = `${completion}, suggestion. Tab to accept. Control i to inspect.`

      expect(announce).toHaveBeenCalledWith(expectedAnnouncement)
    })

    it('completion is over 250 characters', () => {
      const completion =
        'This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text.'
      screenReaderManager.announceCompletion(completion)
      const shortenedCompletion =
        'This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of text. This line of text is a good line of'
      const expectedAnnouncement = `${shortenedCompletion}..., truncated suggestion. Tab to accept. Control i to inspect.`

      expect(announce).toHaveBeenCalledWith(expectedAnnouncement)
    })
  })
})
