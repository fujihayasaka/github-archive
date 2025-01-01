import {useEffect} from 'react'

type UseLinkInterceptionSettings = {
  // Either a ref to the container or the container itself
  // This is needed because the container may not be rendered yet when this hook is called
  htmlContainerRef?: React.RefObject<HTMLElement>
  htmlContainer?: HTMLElement
  onLinkClick?: (event: MouseEvent) => void
  openLinksInNewTab: boolean
}

/**
 * Updates all links in the container to open a new tab and call `onLinkClick` on click.
 */
export const useLinkInterception = ({
  htmlContainerRef,
  htmlContainer,
  onLinkClick,
  openLinksInNewTab,
}: UseLinkInterceptionSettings) => {
  useEffect(() => {
    const theref = htmlContainerRef?.current || htmlContainer

    if (!theref) return

    const clickHandler = (event: MouseEvent) => {
      const link = (event.target as Element).closest('a')
      if (!link) return

      onLinkClick?.(event)

      if (!event.defaultPrevented && openLinksInNewTab && link.href) {
        window.open(link.href, '_blank', 'noopener noreferrer')
        event.preventDefault()
      }
    }

    theref.addEventListener('click', clickHandler)

    return () => {
      theref?.removeEventListener('click', clickHandler)
    }
  }, [htmlContainer, htmlContainerRef, onLinkClick, openLinksInNewTab])
}
