import {MockContentPreviewBlockContextProvider} from '../../../test-utils/MockContentPreviewBlockContextProvider'
import {MockContentPreviewContextProvider} from '../../../test-utils/MockContentPreviewContextProvider'

export function Wrapper({children}: {children: React.ReactNode}) {
  return (
    <MockContentPreviewContextProvider>
      <MockContentPreviewBlockContextProvider>{children}</MockContentPreviewBlockContextProvider>
    </MockContentPreviewContextProvider>
  )
}
