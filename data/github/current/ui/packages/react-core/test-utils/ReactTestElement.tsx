import {controller} from '@github/catalyst'

import type {EmbeddedData} from '../embedded-data-types'
import {ReactBaseElement} from '../ReactBaseElement'

declare global {
  namespace JSX {
    interface IntrinsicElements {
      'react-test': React.DetailedHTMLProps<React.HTMLAttributes<ReactTestElement>, ReactTestElement>
    }
  }
}

@controller
class ReactTestElement extends ReactBaseElement<EmbeddedData> {
  nameAttribute = 'app-name'

  async getReactNode() {
    return <div />
  }

  override disconnectedCallback() {
    /* no-op to prevent react from being disconnected too soon */
  }
}
