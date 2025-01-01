import type {Model} from '@github-ui/marketplace-common'
import {useNavigate} from '@github-ui/use-navigate'
import {SegmentedControl} from '@primer/react'
import {modelPath} from '@github-ui/paths'
import {useState} from 'react'
import {useLocation, useSearchParams} from 'react-router-dom'
import {PlaygroundViewOption, playgroundViewSuffixes} from '../../playground/components/types'

export type ViewSwitcherProps = {
  model: Model
}

function assertValidPlaygroundViewOption(value: number): asserts value is PlaygroundViewOption {
  if (new Set<number>(Object.values(PlaygroundViewOption)).has(value)) return
  throw new Error(`Invalid PlaygroundViewOption "${value}"`)
}

export function ViewSwitcher({model}: ViewSwitcherProps) {
  const navigate = useNavigate()
  const location = useLocation()
  const [searchParams] = useSearchParams()

  const [selectedOption, setSelectedOption] = useState<PlaygroundViewOption>(() => {
    const finalPathComponent = location.pathname.split('/').pop()?.toLowerCase()

    switch (finalPathComponent) {
      case 'evals':
        return PlaygroundViewOption.EVALS
      default:
        return PlaygroundViewOption.PROMPT
    }
  })

  const handleOptionChange = (option: number) => {
    if (option === selectedOption) return
    assertValidPlaygroundViewOption(option)
    setSelectedOption(option)
    const url = modelPath(model)
    const suffix = playgroundViewSuffixes[option]

    navigate({
      pathname: `${url}${suffix}`,
      search: searchParams.toString(),
    })
  }

  return (
    <SegmentedControl aria-label="View mode" onChange={handleOptionChange} size="small">
      <SegmentedControl.Button selected={selectedOption === PlaygroundViewOption.PROMPT}>
        Prompt
      </SegmentedControl.Button>
      <SegmentedControl.Button selected={selectedOption === PlaygroundViewOption.EVALS}>
        Evaluate
      </SegmentedControl.Button>
    </SegmentedControl>
  )
}
