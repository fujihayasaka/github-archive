import {AiModelIcon} from '@primer/octicons-react'
import {Button, Stack} from '@primer/react'

import type {CustomKey} from '../types'
import {getProviderFor} from './providers/Providers'

export function ApiKeys({customKeys}: {customKeys: CustomKey[]}) {
  return customKeys.map(customKey => (
    <Stack.Item
      key={customKey.id}
      grow
      className="Box-row--hover-gray d-flex gap-2 p-3 border-bottom flex-items-center"
    >
      <AiModelIcon size={14} />
      <div className="flex-1">
        <div className="text-bold">{customKey.name}</div>
        <div className="pt-1 text-small fgColor-muted">
          {getProviderFor(customKey.provider).name} &middot; {customKey.totalModels} models
        </div>
      </div>
      <Button size="small" aria-label={`Edit custom key ${customKey.name}`}>
        Edit
      </Button>
    </Stack.Item>
  ))
}
