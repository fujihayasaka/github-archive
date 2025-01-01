import {getFetchNonce} from '@github-ui/fetch-nonce'
import {forwardRef} from 'react'
import {useClientValue} from '@github-ui/use-client-value'

export type IncludeFragmentProps = JSX.IntrinsicElements['include-fragment']

function IncludeFragmentWithRef({children, src, ...props}: IncludeFragmentProps, ref: React.Ref<HTMLElement>) {
  const [isSSR] = useClientValue(() => false, true, [])

  return (
    // eslint-disable-next-line react/forbid-elements
    <include-fragment {...props} ref={ref} {...(isSSR ? {} : {src, 'data-nonce': getFetchNonce()})}>
      {children}
    </include-fragment>
  )
}

export const IncludeFragment = forwardRef(IncludeFragmentWithRef)
