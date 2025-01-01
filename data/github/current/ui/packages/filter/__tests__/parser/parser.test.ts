import {defaultFilterConfig} from '../../Filter'
import {FilterQuery} from '../../filter-query'
import {FilterQueryParser} from '../../parser'
import {
  CreatedFilterProvider,
  IsFilterProvider,
  LabelFilterProvider,
  OrgFilterProvider,
  RepositoryFilterProvider,
  SortFilterProvider,
  StateFilterProvider,
  UserFilterProvider,
} from '../../providers'
import type {IndexedFilterBlock, IndexedGroupBlock} from '../../types'
import {setupLabelsMockApi, setupOrgsMockApi, setupRepositoriesMockApi, setupUsersMockApi} from '../utils/helpers'

const groupingSupportConfig = {
  ...defaultFilterConfig,
  groupAndKeywordSupport: true,
}

describe('FilterQueryParser', () => {
  describe('Parser', () => {
    it('should parse a query', () => {
      const query = 'state:open is:open this is some text'

      const stateProvider = new StateFilterProvider()
      const isProvider = new IsFilterProvider()
      const parser = new FilterQueryParser([stateProvider, isProvider], groupingSupportConfig)

      const result = parser.parse(query, new FilterQuery(query), 10)

      const block1 = result.blocks[0] as IndexedFilterBlock
      const block3 = result.blocks[2] as IndexedFilterBlock

      expect(block1.key.value).toBe('state')
      expect(block1.value.values.length).toBe(1)
      expect(block1.value.values[0]?.value).toBe('open')
      expect(block3.key.value).toBe('is')
      expect(block3.value.values.length).toBe(1)
      expect(block3.value.values[0]?.value).toBe('open')
      expect(block3.value.values[0]?.valid).toBeFalsy()

      expect(result.blocks.length).toBe(11)
      expect(block1.hasCaret).toBeTruthy()
      expect(result.activeBlockId).toBe(0)
    })

    it('should recognize operators for numerical values', async () => {
      const query = 'state:open is:issue created:<10 this is some text'

      const stateProvider = new StateFilterProvider()
      const isProvider = new IsFilterProvider()
      const createdProvider = new CreatedFilterProvider()
      const parser = new FilterQueryParser([stateProvider, isProvider, createdProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query), 10)
      result = await parser.validateFilterQuery(result)

      const block1 = result.blocks[0] as IndexedFilterBlock
      const block2 = result.blocks[2] as IndexedFilterBlock
      const block3 = result.blocks[4] as IndexedFilterBlock
      expect(block1.key.value).toBe('state')
      expect(block1.value.values.length).toBe(1)
      expect(block1.value.values[0]?.value).toBe('open')
      expect(block2.key.value).toBe('is')
      expect(block2.value.values.length).toBe(1)
      expect(block2.value.values[0]?.value).toBe('issue')
      expect(block2.value.values[0]?.valid).toBeTruthy()
      expect(block3.key.value).toBe('created')
      expect(block3.value.values.length).toBe(1)
      expect(block3.value.values[0]?.value).toBe('<10')
      expect(block3.operator).toBe('Before')

      expect(result.blocks.length).toBe(13)
      expect(block1.hasCaret).toBeTruthy()
      expect(result.activeBlockId).toBe(0)
    })

    it('should recognize between operator for numerical values', async () => {
      const query = 'state:open is:issue created:10..20 this is some text'

      const stateProvider = new StateFilterProvider()
      const isProvider = new IsFilterProvider()
      const createdProvider = new CreatedFilterProvider()
      const parser = new FilterQueryParser([stateProvider, isProvider, createdProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query), 10)
      result = await parser.validateFilterQuery(result)

      const block1 = result.blocks[0] as IndexedFilterBlock
      const block2 = result.blocks[2] as IndexedFilterBlock
      const block3 = result.blocks[4] as IndexedFilterBlock
      expect(block1.key.value).toBe('state')
      expect(block1.value.values.length).toBe(1)
      expect(block1.value.values[0]?.value).toBe('open')
      expect(block2.key.value).toBe('is')
      expect(block2.value.values.length).toBe(1)
      expect(block2.value.values[0]?.value).toBe('issue')
      expect(block2.value.values[0]?.valid).toBeTruthy()
      expect(block3.key.value).toBe('created')
      expect(block3.value.values.length).toBe(2)
      expect(block3.value.values[0]?.value).toBe('10')
      expect(block3.value.values[1]?.value).toBe('20')
      expect(block3.operator).toBe('Between')

      expect(result.blocks.length).toBe(13)
      expect(block1.hasCaret).toBeTruthy()
      expect(result.activeBlockId).toBe(0)
    })

    it('should detect unbalanced parentheses', async () => {
      const query = 'state:op (foo'

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      let result = parser.parse(query, new FilterQuery())
      result = await parser.validateFilterQuery(result)

      const parsingErrors = result.getErrors(true)
      expect(parsingErrors).toHaveLength(2)
      expect(parsingErrors[1]).toBe('Unbalanced parentheses')
    })

    it('should detect unbalanced quotations', async () => {
      const query = 'state:op "foo'

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      let result = parser.parse(query, new FilterQuery())
      result = await parser.validateFilterQuery(result)

      const parsingErrors = result.getErrors(true)
      expect(parsingErrors).toHaveLength(2)
      expect(parsingErrors[1]).toBe('Unbalanced quotation marks')
    })

    it("should parse unmatched close parenthesis in filter value as it's own type", async () => {
      const query = 'state:open)'

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query))
      result = await parser.validateFilterQuery(result)

      const block1 = result.blocks[0] as IndexedFilterBlock
      const block2 = result.blocks[1] as IndexedFilterBlock

      expect(block1.key.value).toBe('state')
      expect(block1.value.raw).toBe('open')
      expect(block1.type).toBe('filter')
      expect(block1.raw).toBe('state:open')
      expect(block2.raw).toBe(')')
      expect(block2.type).toBe('unmatched-close-paren')
    })

    it('processes closing parenthesis within a filter value with additional text as a filter block, unmatched, and text', async () => {
      const query = 'state:open)foo bar'
      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query))
      result = await parser.validateFilterQuery(result)

      const block1 = result.blocks[0] as IndexedFilterBlock
      const block2 = result.blocks[1] as IndexedFilterBlock
      const block3 = result.blocks[2] as IndexedFilterBlock
      const block4 = result.blocks[3] as IndexedFilterBlock
      const block5 = result.blocks[4] as IndexedFilterBlock

      expect(block1.raw).toBe('state:open')
      expect(block1.type).toBe('filter')
      expect(block2.raw).toBe(')')
      expect(block2.type).toBe('unmatched-close-paren')
      expect(block3.raw).toBe('foo')
      expect(block3.type).toBe('text')
      expect(block4.raw).toBe(' ')
      expect(block4.type).toBe('space')
      expect(block5.raw).toBe('bar')
      expect(block5.type).toBe('text')
    })

    it('should match provider keys regardless of casing', async () => {
      const query = 'State:OpEn'
      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query))
      result = await parser.validateFilterQuery(result)

      const block1 = result.blocks[0] as IndexedFilterBlock

      expect(block1.raw).toBe('State:OpEn')
      expect(block1.type).toBe('filter')
      expect(block1.valid).toBeTruthy()
    })
  })

  describe('insertSuggestion', () => {
    it('should insert the suggestion at the caret position', () => {
      const query = 'state:op'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), query.length)
      const result = parser.insertSuggestion(queryRequest, 'open', caretPosition)

      expect(result).toStrictEqual(['state:open', 10])
    })

    it('should replace partial suggestions with numerical operators', () => {
      const query = 'comments:<1'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), query.length)
      const result = parser.insertSuggestion(queryRequest, '<10', caretPosition)

      expect(result).toStrictEqual(['comments:<10', 12])
    })

    it('if caret position is negative, it should insert the suggestion at the end of the query', () => {
      const query = 'state:op'
      const caretPosition = -1

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.insertSuggestion(queryRequest, 'open', caretPosition)

      expect(result).toStrictEqual(['state:opopen', 12])
    })

    it('should insert key value suggestions at the caret position', () => {
      const query = 'sta:open'
      const caretPosition = 'sta'.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.insertSuggestion(queryRequest, 'state:', caretPosition)

      expect(result).toStrictEqual(['state:open', 6])
    })

    it('should insert excluded key value suggestions at the caret position', () => {
      const query = '-state:op'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.insertSuggestion(queryRequest, 'open', caretPosition)

      expect(result).toStrictEqual(['-state:open', 11])
    })
  })

  describe('getRaw', () => {
    it('should return the raw query', () => {
      const query = 'state:open'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.getRaw(queryRequest)

      expect(result).toBe('state:open')
    })

    it('should return the raw query when not a filter', () => {
      const query = 'this is a test'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.getRaw(queryRequest)

      expect(result).toBe('this is a test')
    })
  })

  describe('replaceActiveBlockWithPresenceBlock for no: filter', () => {
    it('should replace the active block with a no block', () => {
      const query = 'state:'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.replaceActiveBlockWithPresenceBlock(queryRequest, 'no')

      expect(result).toStrictEqual(['no:state', 8])
    })

    it('should replace the active block with a no block and remove the caret', () => {
      const query = 'state:open'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.replaceActiveBlockWithPresenceBlock(queryRequest, 'no')

      expect(result).toStrictEqual(['no:state', 8])
    })
  })

  describe('replaceActiveBlockWithPresenceBlock for has: filter', () => {
    it('should replace the active block with a has block', () => {
      const query = 'state:'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.replaceActiveBlockWithPresenceBlock(queryRequest, 'has')

      expect(result).toStrictEqual(['has:state', 9])
    })

    it('should replace the active block with a has block and remove the caret', () => {
      const query = 'state:open'
      const caretPosition = query.length

      const stateProvider = new StateFilterProvider()
      const parser = new FilterQueryParser([stateProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), caretPosition)
      const result = parser.replaceActiveBlockWithPresenceBlock(queryRequest, 'has')

      expect(result).toStrictEqual(['has:state', 9])
    })
  })

  describe('validateFilterQuery', () => {
    setupLabelsMockApi()

    it('should validate the filter query', async () => {
      const query = 'state:open is:open this is some text'

      const stateProvider = new StateFilterProvider()
      const isProvider = new IsFilterProvider()
      const parser = new FilterQueryParser([stateProvider, isProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query), 10)
      result = await parser.validateFilterQuery(result)

      const block1 = result.blocks[0] as IndexedFilterBlock
      const block3 = result.blocks[2] as IndexedFilterBlock

      expect(block1.key.value).toBe('state')
      expect(block1.value.values.length).toBe(1)
      expect(block1.value.values[0]?.value).toBe('open')
      expect(block3.key.value).toBe('is')
      expect(block3.value.values.length).toBe(1)
      expect(block3.value.values[0]?.value).toBe('open')
      expect(block3.value.values[0]?.valid).toBeFalsy()

      expect(result.blocks.length).toBe(11)
      expect(block1.hasCaret).toBeTruthy()
      expect(result.activeBlockId).toBe(0)
    })

    it('should validate the filter query with group blocks', async () => {
      const query = 'state:open is:open (label:bug OR label:feature)'

      const stateProvider = new StateFilterProvider()
      const isProvider = new IsFilterProvider()
      const labelProvider = new LabelFilterProvider()
      const parser = new FilterQueryParser([stateProvider, isProvider, labelProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query), 10)
      result = await parser.validateFilterQuery(result)

      const block1 = result.blocks[0] as IndexedFilterBlock
      const block3 = result.blocks[2] as IndexedFilterBlock
      const groupBlock = result.blocks[4] as IndexedGroupBlock

      expect(block1.key.value).toBe('state')
      expect(block1.value.values.length).toBe(1)
      expect(block1.value.values[0]?.value).toBe('open')

      expect(block3.key.value).toBe('is')
      expect(block3.value.values.length).toBe(1)
      expect(block3.value.values[0]?.value).toBe('open')

      expect(groupBlock.blocks.length).toBe(5)

      const groupBlock1 = groupBlock.blocks[0] as IndexedFilterBlock
      const groupBlock3 = groupBlock.blocks[4] as IndexedFilterBlock

      expect(groupBlock1.key.value).toBe('label')
      expect(groupBlock1.value.values.length).toBe(1)
      expect(groupBlock1.value.values[0]?.value).toBe('bug')

      expect(groupBlock3.key.value).toBe('label')
      expect(groupBlock3.value.values.length).toBe(1)
      expect(groupBlock3.value.values[0]?.value).toBe('feature')

      expect(result.blocks.length).toBe(5)
    })

    it('should validate the filter query with nested group blocks', async () => {
      const query = 'state:open is:open (label:bug OR (label:feature AND label:enhancement))'

      const stateProvider = new StateFilterProvider()
      const isProvider = new IsFilterProvider()
      const labelProvider = new LabelFilterProvider()
      const parser = new FilterQueryParser([stateProvider, isProvider, labelProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query), 10)
      result = await parser.validateFilterQuery(result)

      const block1 = result.blocks[0] as IndexedFilterBlock
      const block3 = result.blocks[2] as IndexedFilterBlock
      const groupBlock = result.blocks[4] as IndexedGroupBlock

      expect(block1.key.value).toBe('state')
      expect(block1.value.values.length).toBe(1)
      expect(block1.value.values[0]?.value).toBe('open')

      expect(block3.key.value).toBe('is')
      expect(block3.value.values.length).toBe(1)
      expect(block3.value.values[0]?.value).toBe('open')

      expect(groupBlock.blocks.length).toBe(5)

      const groupBlock1 = groupBlock.blocks[0] as IndexedFilterBlock
      const groupBlock3 = groupBlock.blocks[4] as IndexedGroupBlock

      expect(groupBlock1.key.value).toBe('label')
      expect(groupBlock1.value.values.length).toBe(1)
      expect(groupBlock1.value.values[0]?.value).toBe('bug')

      expect(groupBlock3.blocks.length).toBe(5)

      const nestedGroupBlock1 = groupBlock3.blocks[0] as IndexedFilterBlock
      const nestedGroupBlock3 = groupBlock3.blocks[4] as IndexedFilterBlock

      expect(nestedGroupBlock1.key.value).toBe('label')
      expect(nestedGroupBlock1.value.values.length).toBe(1)
      expect(nestedGroupBlock1.value.values[0]?.value).toBe('feature')

      expect(nestedGroupBlock3.key.value).toBe('label')
      expect(nestedGroupBlock3.value.values.length).toBe(1)
      expect(nestedGroupBlock3.value.values[0]?.value).toBe('enhancement')

      expect(result.blocks.length).toBe(5)
    })

    it('displays warning when max nested groups is exceeded', async () => {
      const query = '((state:open is:issue) (label:bug OR ((label:feature AND ((label:enhancement) OR label:a11y)))))'

      const stateProvider = new StateFilterProvider()
      const isProvider = new IsFilterProvider()
      const labelProvider = new LabelFilterProvider()
      const parser = new FilterQueryParser([stateProvider, isProvider, labelProvider], groupingSupportConfig)

      let result = parser.parse(query, new FilterQuery(query), 10)
      result = await parser.validateFilterQuery(result)

      const parsingErrors = result.getErrors(true)
      expect(parsingErrors).toHaveLength(1)
      expect(parsingErrors[0]).toBe('Maximum nested groups of 5 exceeded')
    })

    describe('User', () => {
      setupUsersMockApi()

      it('displays warning when filter within groups', async () => {
        const query = '(state:open OR user:monalisa) state:closed'

        const stateProvider = new StateFilterProvider()
        const userProvider = new UserFilterProvider({
          currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
          currentUserLogin: 'monalisa',
        })
        const parser = new FilterQueryParser([stateProvider, userProvider], groupingSupportConfig)

        let result = parser.parse(query, new FilterQuery(query), 10)
        result = await parser.validateFilterQuery(result)

        const parsingErrors = result.getErrors(true)
        expect(parsingErrors).toHaveLength(1)
        expect(parsingErrors[0]).toBe('Filter <pre>user</pre> cannot be used within groups')
      })

      it('does not display warning when filter is not within groups', async () => {
        const query = 'state:open user:monalisa state:closed'

        const stateProvider = new StateFilterProvider()
        const userProvider = new UserFilterProvider({
          currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
          currentUserLogin: 'monalisa',
        })
        const parser = new FilterQueryParser([stateProvider, userProvider], groupingSupportConfig)

        let result = parser.parse(query, new FilterQuery(query), 10)
        result = await parser.validateFilterQuery(result)

        const parsingErrors = result.getErrors(true)
        expect(parsingErrors).toHaveLength(0)
      })
    })

    describe('Repo', () => {
      setupRepositoriesMockApi()

      it('displays warning when filter within groups', async () => {
        const query = '(state:open OR repo:github/github) state:closed'

        const stateProvider = new StateFilterProvider()
        const repoProvider = new RepositoryFilterProvider()
        const parser = new FilterQueryParser([stateProvider, repoProvider], groupingSupportConfig)

        let result = parser.parse(query, new FilterQuery(query), 10)
        result = await parser.validateFilterQuery(result)

        const parsingErrors = result.getErrors(true)
        expect(parsingErrors).toHaveLength(1)
        expect(parsingErrors[0]).toBe('Filter <pre>repo</pre> cannot be used within groups')
      })

      it('does not display warning when filter is not within groups', async () => {
        const query = 'state:open repo:github/github state:closed'

        const stateProvider = new StateFilterProvider()
        const repoProvider = new RepositoryFilterProvider()
        const parser = new FilterQueryParser([stateProvider, repoProvider], groupingSupportConfig)

        let result = parser.parse(query, new FilterQuery(query), 10)
        result = await parser.validateFilterQuery(result)

        const parsingErrors = result.getErrors(true)
        expect(parsingErrors).toHaveLength(0)
      })
    })

    describe('Org', () => {
      setupOrgsMockApi()

      it('displays warning when filter within groups', async () => {
        const query = '(state:open OR org:github) state:closed'

        const stateProvider = new StateFilterProvider()
        const orgProvider = new OrgFilterProvider()
        const parser = new FilterQueryParser([stateProvider, orgProvider], groupingSupportConfig)

        let result = parser.parse(query, new FilterQuery(query), 10)
        result = await parser.validateFilterQuery(result)

        const parsingErrors = result.getErrors(true)
        expect(parsingErrors).toHaveLength(1)
        expect(parsingErrors[0]).toBe('Filter <pre>org</pre> cannot be used within groups')
      })

      it('does not display warning when filter is not within groups', async () => {
        const query = 'state:open org:github state:closed'

        const stateProvider = new StateFilterProvider()
        const orgProvider = new OrgFilterProvider()
        const parser = new FilterQueryParser([stateProvider, orgProvider], groupingSupportConfig)

        let result = parser.parse(query, new FilterQuery(query), 10)
        result = await parser.validateFilterQuery(result)

        const parsingErrors = result.getErrors(true)
        expect(parsingErrors).toHaveLength(0)
      })
    })

    describe('Sort', () => {
      it('displays warning when filter within groups', async () => {
        const query = '(state:open OR sort:created-asc) state:closed'

        const stateProvider = new StateFilterProvider()
        const sortProvider = new SortFilterProvider(['created'])
        const parser = new FilterQueryParser([stateProvider, sortProvider], groupingSupportConfig)

        let result = parser.parse(query, new FilterQuery(query), 10)
        result = await parser.validateFilterQuery(result)

        const parsingErrors = result.getErrors(true)
        expect(parsingErrors).toHaveLength(1)
        expect(parsingErrors[0]).toBe('Filter <pre>sort</pre> cannot be used within groups')
      })

      it('does not display warning when filter is not within groups', async () => {
        const query = 'state:open sort:created-asc state:closed'

        const stateProvider = new StateFilterProvider()
        const sortProvider = new SortFilterProvider(['created'])
        const parser = new FilterQueryParser([stateProvider, sortProvider], groupingSupportConfig)

        let result = parser.parse(query, new FilterQuery(query), 10)
        result = await parser.validateFilterQuery(result)

        const parsingErrors = result.getErrors(true)
        expect(parsingErrors).toHaveLength(0)
      })
    })
  })

  describe('Inserts suggestions handling parenthesis', () => {
    it('should replace partial parenthesis suggestions with quotations', () => {
      const query = 'label:coo'
      const caretPosition = query.length

      const labelProvider = new LabelFilterProvider()

      const parser = new FilterQueryParser([labelProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), query.length)
      const result = parser.insertSuggestion(queryRequest, '"(cool"', caretPosition)

      expect(result).toStrictEqual(['label:"(cool"', 13])
    })

    it('should not replace an opening parenthesis when a filter is chosen', () => {
      const query = '(lab'
      const caretPosition = query.length

      const labelProvider = new LabelFilterProvider()

      const parser = new FilterQueryParser([labelProvider], groupingSupportConfig)
      const queryRequest = parser.parse(query, new FilterQuery(), query.length)
      const result = parser.insertSuggestion(queryRequest, 'label', caretPosition)

      expect(result).toStrictEqual(['(label', 6])
    })
  })
})
