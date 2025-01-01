import {useCurrentRepository} from '@github-ui/current-repository'
import {repoModelsPromptPath, repoPromptNewPath} from '@github-ui/paths'
import {useNavigate} from '@github-ui/use-navigate'
import {SegmentedControl} from '@primer/react'
import {useState} from 'react'
import {useLocation, useParams} from 'react-router-dom'
import styles from './ViewSwitcher.module.css'
import {isPromptComparePage} from '../prompts'

type PlaygroundViewOption = 'prompt' | 'compare'

interface ViewSwitcherProps {
  disabled?: boolean
}

export function ViewSwitcher({disabled = false}: ViewSwitcherProps) {
  const navigate = useNavigate()
  const location = useLocation()

  const {'*': path, branch} = useParams()

  const repo = useCurrentRepository()
  // If the path is empty, we are on the new prompt page
  const isNewPrompt = location.pathname.endsWith('compare/main')

  const [selectedOption, setSelectedOption] = useState<PlaygroundViewOption>(() => {
    return isPromptComparePage(location.pathname) ? 'compare' : 'prompt'
  })

  const handleOptionChange = (idx: number) => {
    if (disabled) {
      return
    }
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
        pathname: isNewPrompt
          ? repoPromptNewPath(repo)
          : repoModelsPromptPath({
              repo,
              path,
              commitish: branch || repo.defaultBranch,
              action: 'edit',
            }),
      })
    }
  }

  return (
    <SegmentedControl
      className={`mb-3 mb-md-0 ${styles.smallSize}`}
      aria-label="View mode"
      size="small"
      onChange={handleOptionChange}
    >
      <SegmentedControl.Button className={styles.smallSize} selected={selectedOption === 'prompt'} disabled={disabled}>
        Edit
      </SegmentedControl.Button>
      <SegmentedControl.Button className={styles.smallSize} selected={selectedOption === 'compare'} disabled={disabled}>
        Compare
      </SegmentedControl.Button>
    </SegmentedControl>
  )
}
