import {DisplayData} from '../components/DisplayData'
import {indexRoute} from './index-route'

export function Index() {
  return (
    <>
      <p data-hpc>App Index</p>
      <DisplayData route={indexRoute} />

      <p>
        <a id="foo-anchor" href="#foo">
          Go to #foo
        </a>
      </p>
      <p>
        <a id="bar-anchor" href="#bar">
          Go to #bar
        </a>
      </p>

      <h2 id="foo">Foo</h2>
      <h2 id="bar">Bar</h2>
    </>
  )
}
