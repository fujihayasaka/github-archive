import { on } from 'delegated-events'

on('click', '[data-toggles]', function (event) {
  const toggler = event.currentTarget!
  const toggleTargetId = toggler.getAttribute('data-toggles')!
  const toggleTarget = document.getElementById(toggleTargetId)!
  const togglingOn = toggler.getAttribute('aria-selected') !== 'true'

  const toggleOpenElement = document.getElementById(`${toggleTargetId}-open`)
  const toggleCloseElement = document.getElementById(`${toggleTargetId}-close`)

  toggleOpenElement?.toggleAttribute('hidden', togglingOn)
  toggleCloseElement?.toggleAttribute('hidden', !togglingOn)

  toggleTarget.hidden = !togglingOn
  toggler.setAttribute('aria-selected', togglingOn.toString())
})
