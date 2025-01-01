import {Box, Text, IconButton} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {ThreeBarsIcon, MarkGithubIcon} from '@primer/octicons-react'

// 🚨 Note: This is a fake component mimicking our global navigation.

function GlobalNavigation() {
  return (
    <Box as="header" sx={{bg: 'canvas.inset', width: '100%', maxWidth: '100%'}}>
      <Box
        sx={{
          px: 3,
          pt: 3,
          pb: 3,
          display: 'flex',
          gap: 3,
          alignItems: 'center',
          borderBottomColor: 'border.default',
          borderBottomWidth: 1,
          borderBottomStyle: 'solid',
        }}
      >
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton unsafeDisableTooltip icon={ThreeBarsIcon} aria-label="Menu" />
        <Octicon icon={MarkGithubIcon} size={32} />
        <Box sx={{display: 'flex', gap: 2}}>
          <Text sx={{fontSize: 1, fontWeight: 'bold'}}>Settings</Text>
        </Box>
      </Box>
    </Box>
  )
}

export default GlobalNavigation
