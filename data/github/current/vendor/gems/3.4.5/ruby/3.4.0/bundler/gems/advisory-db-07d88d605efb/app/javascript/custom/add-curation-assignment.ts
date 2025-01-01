import { on } from 'delegated-events'

on('click', '.js-assignment', () => {
  const assignment =
    document.querySelector<HTMLTemplateElement>('#drop-down-curator')

  if (!assignment) return
  const new_assignment = assignment.content.cloneNode(true)
  document.querySelector('.js-assign-curator-list')!.appendChild(new_assignment)
})
