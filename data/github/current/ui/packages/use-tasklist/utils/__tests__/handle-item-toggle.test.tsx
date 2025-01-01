// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {handleItemToggle} from '../handle-item-toggle'

describe('handleItemToggle', () => {
  test('toggles the checked state of the task item', () => {
    const markdownValue = '- [ ] 0.0 Task item'
    const markdownIndex = 0
    const onChange = jest.fn()

    handleItemToggle({markdownValue, markdownIndex, onChange})

    expect(onChange).toHaveBeenCalledWith('- [x] 0.0 Task item')
  })

  test('toggles the unchecked state of the task item', () => {
    const markdownValue = '- [x] 0.0 Task item'
    const markdownIndex = 0
    const onChange = jest.fn()

    handleItemToggle({markdownValue, markdownIndex, onChange})

    expect(onChange).toHaveBeenCalledWith('- [ ] 0.0 Task item')
  })

  test('toggles the correct task item when there is a comment block in the markdown', () => {
    const markdownValue = `
      ## Task list 1
      - [ ] Visible 1

      ## Task list 2
      <!-- for task type X
      - [ ] Hidden 1
      -->

       ## Task list 3
      - [ ] Visible 3.1
      `
    const markdownIndex = 1
    const onChange = jest.fn()

    handleItemToggle({markdownValue, markdownIndex, onChange})

    const expectedMarkdown = `
      ## Task list 1
      - [ ] Visible 1

      ## Task list 2
      <!-- for task type X
      - [ ] Hidden 1
      -->

       ## Task list 3
      - [x] Visible 3.1
      `
    expect(onChange).toHaveBeenCalledWith(expectedMarkdown)
  })
})
