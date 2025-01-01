import {textDiff} from '../grouped-text-diff'

test('additions to be correctly calculated on the diff', () => {
  const wordToAdd = 'addme'
  const basicAddition = textDiff({before: undefined, after: wordToAdd})
  expect(basicAddition.lines.length).toBe(1)
  expect(basicAddition.lines[0]!.modification).toBe('ADDED')
  expect(basicAddition.lines[0]!.groups.length).toBe(1)
  expect(basicAddition.lines[0]!.groups[0]!.modification).toBe('ADDED')
  expect(basicAddition.lines[0]!.groups[0]!.words).toBe(wordToAdd)
})

test('deletions to be correctly calculated on the diff', () => {
  const wordToDelete = 'deleteme'
  const basicDeletion = textDiff({before: wordToDelete, after: undefined})
  expect(basicDeletion.lines.length).toBe(1)
  expect(basicDeletion.lines[0]!.modification).toBe('REMOVED')
  expect(basicDeletion.lines[0]!.groups.length).toBe(1)
  expect(basicDeletion.lines[0]!.groups[0]!.modification).toBe('REMOVED')
  expect(basicDeletion.lines[0]!.groups[0]!.words).toBe(wordToDelete)
})

test('edits on the same line to be correctly calculated on the diff', () => {
  const wordToEdit = 'editme'
  const wordEdited = 'edited'
  const basicEdit = textDiff({before: wordToEdit, after: wordEdited})

  expect(basicEdit.lines.length).toBe(1)
  expect(basicEdit.lines[0]!.modification).toBe('EDITED')
  expect(basicEdit.lines[0]!.groups.length).toBe(2)
  expect(basicEdit.lines[0]!.groups[0]!.modification).toBe('ADDED')
  expect(basicEdit.lines[0]!.groups[0]!.words).toBe(wordEdited)
  expect(basicEdit.lines[0]!.groups[1]!.modification).toBe('REMOVED')
  expect(basicEdit.lines[0]!.groups[1]!.words).toBe(wordToEdit)
})

test('groups add and remove edits on the same line', () => {
  const beforeParagraph = `This is a paragraph
  DELETE THIS`
  const afterParagraph = `This is a paragraph
  NEW WITH MORE WORDS`

  const complexEdit = textDiff({before: beforeParagraph, after: afterParagraph})

  expect(complexEdit.lines.length).toBe(2)
  expect(complexEdit.lines[0]!.modification).toBe('UNCHANGED')
  expect(complexEdit.lines[1]!.modification).toBe('EDITED')
  expect(complexEdit.lines[1]!.groups.length).toBe(2)
  expect(complexEdit.lines[1]!.groups[0]!.modification).toBe('ADDED')
  expect(complexEdit.lines[1]!.groups[0]!.words).toBe('NEW WITH MORE WORDS')
  expect(complexEdit.lines[1]!.groups[1]!.modification).toBe('REMOVED')
  expect(complexEdit.lines[1]!.groups[1]!.words).toBe('DELETE THIS')
})

test('matches unchanged words between edits', () => {
  const beforeParagraph = `This is a paragraph
  DELETE THIS THING`
  const afterParagraph = `This is a paragraph
  NEW THIS MORE WORDS`

  const complexEdit = textDiff({before: beforeParagraph, after: afterParagraph})

  expect(complexEdit.lines.length).toBe(2)
  expect(complexEdit.lines[0]!.modification).toBe('UNCHANGED')
  expect(complexEdit.lines[1]!.modification).toBe('EDITED')
  expect(complexEdit.lines[1]!.groups.length).toBe(5)
  expect(complexEdit.lines[1]!.groups[0]!.modification).toBe('ADDED')
  expect(complexEdit.lines[1]!.groups[0]!.words).toBe('NEW')
  expect(complexEdit.lines[1]!.groups[1]!.modification).toBe('REMOVED')
  expect(complexEdit.lines[1]!.groups[1]!.words).toBe('DELETE')
  expect(complexEdit.lines[1]!.groups[2]!.modification).toBe('UNCHANGED')
  expect(complexEdit.lines[1]!.groups[2]!.words).toBe('THIS')
  expect(complexEdit.lines[1]!.groups[3]!.modification).toBe('ADDED')
  expect(complexEdit.lines[1]!.groups[3]!.words).toBe('MORE WORDS')
  expect(complexEdit.lines[1]!.groups[4]!.modification).toBe('REMOVED')
  expect(complexEdit.lines[1]!.groups[4]!.words).toBe('THING')
})

test('all three operations in one edit', () => {
  const beforeParagraph = `This is a paragraph

  DELETE THIS`

  const afterParagraph = `This is a paragraph
  NEW`

  const complexEdit = textDiff({before: beforeParagraph, after: afterParagraph})

  expect(complexEdit.lines.length).toBe(3)
  expect(complexEdit.lines.map(line => line.modification)).toMatchObject(['UNCHANGED', 'ADDED', 'REMOVED'])
})
