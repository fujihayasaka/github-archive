import {accessPolicyShow} from '@github-ui/github-models-org-settings/routes/access-policy-show'
import {Button, Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useCallback, useRef, useState} from 'react'

import {useCurrentOrg} from '../contexts/CurrentOrgContext'
import {setBanner} from '../contexts/PageBannerContext'
import type {CustomModelsIndexMutationData} from '../types'
import {AddKeyDialog} from './AddKeyDialog'

export function AddCustomKeyButton({
  onSuccess,
  publicKey,
}: {
  onSuccess?: (data: CustomModelsIndexMutationData) => void
  publicKey: string
}) {
  const ref = useRef<HTMLButtonElement>(null)

  const org = useCurrentOrg()

  const [show, setShow] = useState(false)

  const onSuccessHandler = useCallback(
    (data: CustomModelsIndexMutationData) => {
      setShow(false)
      setBanner(
        <Banner
          role="banner"
          title="Success"
          variant="success"
          hideTitle
          description={
            <>
              Custom key &quot;<strong>{data.name}</strong>&quot; successfully added. Go to{' '}
              <Link href={accessPolicyShow.generatePath({org})} inline>
                Models Permissions
              </Link>{' '}
              if you want to configure specific settings for custom models.
            </>
          }
        />,
      )
      onSuccess?.(data)
    },
    [org, onSuccess],
  )

  return (
    <>
      <Button ref={ref} variant="primary" onClick={() => setShow(true)}>
        Add custom key
      </Button>

      {show && (
        <AddKeyDialog
          anchorRef={ref}
          onCancel={() => setShow(false)}
          onSuccess={onSuccessHandler}
          publicKey={publicKey}
        />
      )}
    </>
  )
}
