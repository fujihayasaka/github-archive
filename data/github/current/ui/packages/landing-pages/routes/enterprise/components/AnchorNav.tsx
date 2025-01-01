import {useEffect} from 'react'

import {AnchorNav} from '@primer/react-brand'

export default function AnchorNavSection() {
  useEffect(() => {
    const anchorNavEl = document.getElementById('anchor-nav')
    const nextSiblingEl = document.getElementById('scale')
    if (!nextSiblingEl || !anchorNavEl) return

    const anchorNavHeight = anchorNavEl.getBoundingClientRect().height

    const observer = new MutationObserver(mutations => {
      for (const mutation of mutations) {
        if (mutation.attributeName === 'data-sticky') {
          if (mutation.target instanceof HTMLElement) {
            const dataSticky = mutation.target.getAttribute('data-sticky')
            if (dataSticky === 'true' && nextSiblingEl instanceof HTMLElement) {
              nextSiblingEl.style.paddingTop = `${anchorNavHeight}px`
            } else if (nextSiblingEl instanceof HTMLElement) {
              nextSiblingEl.style.paddingTop = '0px'
            }
          }
        }
      }
    })

    observer.observe(anchorNavEl, {attributes: true})

    return () => {
      observer.disconnect()
    }
  }, [])

  return (
    <AnchorNav hideUntilSticky id="anchor-nav">
      <AnchorNav.Link href="#scale">Scale</AnchorNav.Link>

      <AnchorNav.Link href="#ai">AI</AnchorNav.Link>

      <AnchorNav.Link href="#security">Security</AnchorNav.Link>

      <AnchorNav.Link href="#reliability">Reliability</AnchorNav.Link>

      <AnchorNav.Action href="/organizations/enterprise_plan?ref_cta=Start+a+free+trial&ref_loc=navigation&ref_page=%2Fenterprise">
        Start a free trial
      </AnchorNav.Action>
    </AnchorNav>
  )
}
