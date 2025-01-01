import {forwardRef} from 'react'
import {SharedMarkdownContent} from '@github-ui/code-view-shared/components/SharedMarkdownContent'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {MissingCombinationPlaceholder} from './MissingCombinationPlaceholder'
import {testIdProps} from '@github-ui/test-id-props'
import styles from './MarkdownContent.module.css'
import {Heading} from '@primer/react'

interface MarkdownContentProps {
  payload: SafeHTMLString
}

const MarkdownContent = forwardRef<HTMLDivElement, MarkdownContentProps>(({payload}, ref) => {
  const gettingStartedContent = payload

  return (
    <div className={styles.markdownContentWrapper} ref={ref} {...testIdProps('markdown-content')}>
      {/*
          We need to suppress the hydration warning because some of the HTML rendered here (e.g. clipboard copy)
          relies on behaviors/ non-React JS to replace meta- tags with other elements. When React goes to hydrate,
          it will see that the HTML has changed and throw an warning. We can safely suppress this warning because
          the content is static, so it's OK if the client re-render doesn't actually get written to the page.

          Right now we overriding the styles using the sx prop. In the future we want to handle this better.
      */}

      {gettingStartedContent ? (
        <>
          <Heading as="h2" className={styles.getStartedHeader}>
            Or set it up yourself...
          </Heading>
          <Heading as="h3" className={styles.gettingStartedSubtitle}>
            Get started
          </Heading>
          <div className="readme pb-3">
            <SharedMarkdownContent
              suppressHydrationWarning
              richText={gettingStartedContent}
              className={styles.markdownContent}
            />
          </div>
        </>
      ) : (
        <MissingCombinationPlaceholder />
      )}
    </div>
  )
})

MarkdownContent.displayName = 'MarkdownContent'

export default MarkdownContent
