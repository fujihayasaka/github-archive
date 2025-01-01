import {controller} from '@github/catalyst'
import type {ErrorContext} from '@github-ui/failbot'
import type {ReactPartialAnchorElement} from '@github-ui/react-partial-anchor-element'

import {createBrowserHistory} from './create-browser-history'
import type {EmbeddedPartialData} from './embedded-data-types'
import {PartialEntry} from './PartialEntry'
import {Profiler, ProfilerProvider} from './ProfilerContext'
import {getPartialAnchorProps} from './react-partial-anchor'
import {getReactPartial} from './react-partial-registry'
import {ReactBaseElement} from './ReactBaseElement'

// What is this silliness? Is it react or a web component?!
// It's a web component we use to bootstrap react partials within the monolith.
@controller
class ReactPartialElement extends ReactBaseElement<EmbeddedPartialData> {
  nameAttribute = 'partial-name'

  async getReactNode(embeddedData: EmbeddedPartialData, onError: (error: Error, context?: ErrorContext) => void) {
    const {Component} = await getReactPartial(this.name)

    // Some React Partials will be wrapped in a react-partial-anchor, which is used to conditionally render the Partial
    const anchorElement = this.closest<ReactPartialAnchorElement>('react-partial-anchor')

    const history = createBrowserHistory({window})

    const partialAnchorProps = getPartialAnchorProps(anchorElement)

    const mergedEmbeddedData = {
      ...embeddedData,
      props: {
        ...embeddedData.props,
        ...partialAnchorProps,
      },
    }
    return (
      <ProfilerProvider appName={this.name} isDataRouterEnabled={false}>
        <Profiler id={this.name}>
          <PartialEntry
            partialName={this.name}
            embeddedData={mergedEmbeddedData}
            Component={Component}
            wasServerRendered={this.hasSSRContent}
            ssrError={this.ssrError}
            anchorElement={anchorElement}
            onError={onError}
            history={history}
          />
        </Profiler>
      </ProfilerProvider>
    )
  }
}
