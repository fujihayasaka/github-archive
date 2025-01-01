import {applyUnclosedFormatting} from '../extensions/streaming'

describe('applyUnclosedFormatting', () => {
  it.each([
    ['**hello', '**hello**'],
    ['**hello**', '**hello**'],
    ['hello _world', 'hello _world_'],
    ['hello _world ~~goodbye', 'hello _world ~~goodbye~~_'],
    ['hello **world _peace and joy!', 'hello **world _peace and joy!_**'],
    ['here is **an** a [link', 'here is **an** a [link](#)'],
    ['here is **an** a [link](example.com', 'here is **an** a [link](example.com)'],
    ['he**llo', 'he**llo'],
  ])('closes unclosed tags in correct order (%s)', (input, output) =>
    expect(applyUnclosedFormatting(input)).toBe(output),
  )
})
