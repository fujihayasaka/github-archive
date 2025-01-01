import {DisplayQueries} from '../components/DisplayQueries'
import {FooterLinks} from '../components/FooterLinks'
import {SpaceFiller} from '../components/SpaceFiller'
import {reactSandboxFutureIndexRoute} from './index-route'

export function ReactSandboxFutureIndex() {
  return (
    <>
      <h2 data-hpc>ReactSandboxFutureIndex</h2>
      <DisplayQueries route={reactSandboxFutureIndexRoute} />

      <SpaceFiller />

      <FooterLinks />
    </>
  )
}
