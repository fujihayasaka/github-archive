import {clsx} from 'clsx'

import styles0 from './StyledInputBlocks.module.css'

export const TextBlock = ({text}: {text: string}) => <span className="text-block">{text}</span>

export const SpaceBlock = ({text}: {text: string}) => <span className="delimiter space-delimiter">{text}</span>

export const Delimiter = ({delimiter}: {delimiter: string}) => <span className="delimiter">{delimiter}</span>

export const KeywordBlock = ({keyword}: {keyword: string}) => (
  <span className={clsx('keyword-block', styles0.Text_0)}>{keyword}</span>
)

export const KeyBlock = ({text, className}: {text: string; className?: string}) => (
  <span data-type="filter" className={className}>
    {text}
  </span>
)
