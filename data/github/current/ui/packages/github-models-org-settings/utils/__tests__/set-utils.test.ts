import {areSetsDisjoint, isSubsetOf, setDifference, setIntersection} from '../set-utils'

describe('set-utils', () => {
  describe('setIntersection', () => {
    it('returns the intersection of the given sets', () => {
      const set1 = new Set(['a', 'b', 'c'])
      const set2 = new Set(['c', 'd'])

      const result = setIntersection(set1, set2)

      expect(result).toEqual(new Set(['c']))
    })
  })

  describe('areSetsDisjoint', () => {
    it('returns true if the two sets have no value in common', () => {
      const set1 = new Set(['a', 'b', 'c'])
      const set2 = new Set(['d', 'e'])

      const result = areSetsDisjoint(set1, set2)

      expect(result).toEqual(true)
    })

    it('returns false if the sets have a common value', () => {
      const set1 = new Set(['a', 'b', 'c'])
      const set2 = new Set(['c', 'd'])

      const result = areSetsDisjoint(set1, set2)

      expect(result).toEqual(false)
    })
  })

  describe('isSubsetOf', () => {
    it('returns true if all elements of the second set are in the first', () => {
      const set1 = new Set(['a', 'b', 'c', 'd'])
      const set2 = new Set(['a', 'b', 'c'])

      const result = isSubsetOf(set1, set2)

      expect(result).toEqual(true)
    })

    it('returns false if not all elements of the second set are in the first', () => {
      const set1 = new Set(['a', 'b', 'c'])
      const set2 = new Set(['a', 'b', 'c', 'd'])

      const result = isSubsetOf(set1, set2)

      expect(result).toEqual(false)
    })
  })

  describe('setDifference', () => {
    it('returns one set minus the other', () => {
      const set1 = new Set(['a', 'b', 'c', 'd'])
      const set2 = new Set(['b', 'd', 'f', 'h'])

      const result = setDifference(set1, set2)

      expect(result).toEqual(new Set(['a', 'c']))
    })
  })
})
