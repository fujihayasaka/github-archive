/*
 * Shown when the user has reached the 30h compute time limit
 * and the Sparks have been unpublished.
 */

import {Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'

export function ComputeLimitBanner() {
  const description = (
    <>
      You have reached your editing limit for Spark this month. If you would like higher usage limits,{' '}
      <Link inline href="https://gh.io/spark-higher-limits-request" target="_blank" rel="noopener noreferrer">
        contact our team
      </Link>
      .
    </>
  )
  const title = 'Spark editing limit reached.'
  const variant = 'warning'

  return <Banner className="mx-3 mb-2" description={description} hideTitle title={title} variant={variant} />
}
