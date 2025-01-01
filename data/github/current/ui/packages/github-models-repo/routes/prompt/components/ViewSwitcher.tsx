import {useCurrentRepository} from '@github-ui/current-repository'
import {repoModelsPromptPath} from '@github-ui/paths'
import {useNavigate} from '@github-ui/use-navigate'
import {SegmentedControl} from '@primer/react'
import {useState} from 'react'
import {useLocation, useParams} from 'react-router-dom'
import styles from './ViewSwitcher.module.css'

type PlaygroundViewOption = 'prompt' | 'compare'

export function ViewSwitcher() {
  const navigate = useNavigate()
  const location = useLocation()

  const {'*': path, branch} = useParams()

  const repo = useCurrentRepository()

  const [selectedOption, setSelectedOption] = useState<PlaygroundViewOption>(() => {
    return location.pathname.includes('models/prompt/compare') ? 'compare' : 'prompt'
  })

  const handleOptionChange = (idx: number) => {
    const option = (idx === 0 ? 'prompt' : 'compare') as PlaygroundViewOption

    if (option === selectedOption) return
    setSelectedOption(option)

    if (option === 'compare') {
      navigate({
        pathname: repoModelsPromptPath({
          repo,
          path,
          commitish: branch || repo.defaultBranch,
          action: 'compare',
        }),
      })
    } else {
      // Switch to edit
      navigate({
        pathname: repoModelsPromptPath({
          repo,
          path,
          commitish: branch || repo.defaultBranch,
          action: 'edit',
        }),
      })
    }
  }

  return (
    <SegmentedControl className={styles.smallSize} aria-label="View mode" size="small" onChange={handleOptionChange}>
      <SegmentedControl.Button className={styles.smallSize} selected={selectedOption === 'prompt'}>
        Prompt
      </SegmentedControl.Button>
      <SegmentedControl.Button className={styles.smallSize} selected={selectedOption === 'compare'}>
        Compare
      </SegmentedControl.Button>
    </SegmentedControl>
  )
}
