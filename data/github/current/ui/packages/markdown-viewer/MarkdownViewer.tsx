import {forwardRef, useCallback, useMemo, useRef, useState} from 'react'
import {Box, Spinner, useRefObjectAsForwardedRef} from '@primer/react'
import {type SafeHTMLProps, type SafeHTMLString, SafeHTMLBox} from '@github-ui/safe-html'

import {useLinkInterception} from '@github-ui/use-link-interception'
import {useListInteraction} from './use-list-interaction'
import {clsx} from 'clsx'

type CoreMarkdownViewerProps = Omit<SafeHTMLProps, 'html'> & {
  /** Show a loading spinner instead of content. */
  loading?: boolean
  /**
   * Set the rendered HTML of the viewer. To prevent XSS, ensure that the source of this
   * HTML is trusted!
   */
  verifiedHTML: SafeHTMLString
  /**
   * Called when the user clicks a link element. This can be used to intercept the click
   * and provide custom routing. Note that this is a native HTML `MouseEvent` and not a
   * `React.ClickEvent`.
   */
  onLinkClick?: (event: MouseEvent) => void
  openLinksInNewTab?: boolean
  teamHovercardsEnabled?: boolean
  /**
   * Additional class name to apply to the container element.
   */
  className?: string
}

export type InteractiveMarkdownViewerProps = CoreMarkdownViewerProps & {
  /**
   * The markdown the HTML was rendered from. This is not used for viewing, only as a source
   * for change events.
   */
  markdownValue: string
  /**
   * Called when the user interacts and updates the Markdown. The rendered Markdown is
   * updated eagerly - if the request fails, a rejected Promise should be returned by
   * this handler. In that case, the viewer will revert the visual change.
   *
   * If the change is handled by an async API request (as it typically will be in production
   * code), the viewer should be `disabled` while the request is pending to avoid conflicts.
   * To allow users to check multiple boxes rapidly, the API request should be debounced (an
   * ideal debounce duration is about 1 second).
   */
  onChange: (markdown: string) => void | Promise<void>
  /** Control whether interaction is disabled. */
  disabled?: boolean
}

type NoninteractiveMarkdownViewerProps = CoreMarkdownViewerProps & {
  // This is externally useless, but internally it lets us use unpacking to get the props.
  // If a prop was present only on one member of the type union, Typescript would treat it as
  // though it doesn't exist at all until you discriminate which type the props are.
  markdownValue?: undefined
  onChange?: undefined
  disabled?: undefined
}

export type MarkdownViewerProps = NoninteractiveMarkdownViewerProps | InteractiveMarkdownViewerProps

export const MarkdownViewer = forwardRef<HTMLDivElement, MarkdownViewerProps>(function MarkdownViewer(
  {
    verifiedHTML,
    loading = false,
    markdownValue = '',
    onChange: externalOnChange,
    disabled = false,
    onLinkClick,
    openLinksInNewTab = false,
    teamHovercardsEnabled = false,
    className,
  }: MarkdownViewerProps,
  ref,
) {
  // We're using state to store the HTML container because we want the value
  // to re-run effects when it changes
  const [htmlContainer, setHtmlContainer] = useState<HTMLDivElement | null>(null)

  // It's tempting to just `useImperativeHandle(ref, () => htmlContainer, [htmlContainer])`, however this doesn't work
  // in practice because `useEffect`-based code expects refs to be set on the first render. If you do it that way, the
  // ref will be `null` on first render and only set on re-render. So we instead do this annoying bit where we set
  // both a ref object and the state in the callback.
  const htmlContainerRefObject = useRef<HTMLDivElement | null>(null)
  useRefObjectAsForwardedRef(ref, htmlContainerRefObject)

  const htmlContainerRef = useCallback((el: HTMLDivElement | null) => {
    htmlContainerRefObject.current = el
    setHtmlContainer(el)
  }, [])

  const onChange = useCallback(
    async (value: string) => {
      try {
        await externalOnChange?.(value)
      } catch {
        if (htmlContainer) {
          // eslint-disable-next-line react-compiler/react-compiler
          htmlContainer.innerHTML = verifiedHTML
        }
      }
    },
    [externalOnChange, htmlContainer, verifiedHTML],
  )

  useListInteraction({
    onChange,
    disabled: disabled || !externalOnChange,
    htmlContainer: htmlContainer ?? undefined,
    markdownValue,
    dependencies: [verifiedHTML],
  })

  useLinkInterception({
    htmlContainer: htmlContainer ?? undefined,
    onLinkClick,
    openLinksInNewTab,
  })

  return useMemo(
    () =>
      loading ? (
        <Box sx={{display: 'flex', justifyContent: 'space-around', p: 2}}>
          <Spinner aria-label="Loading content..." />
        </Box>
      ) : (
        <SafeHTMLBox
          ref={htmlContainerRef}
          className={clsx('markdown-body', className)}
          sx={className ? {} : {fontSize: 1, maxWidth: '100%', '& > div > :last-child': {mb: 0}}}
          html={verifiedHTML}
          {...(teamHovercardsEnabled ? {'data-team-hovercards-enabled': true} : {})}
        />
      ),
    [className, loading, teamHovercardsEnabled, verifiedHTML, htmlContainerRef],
  )
})
