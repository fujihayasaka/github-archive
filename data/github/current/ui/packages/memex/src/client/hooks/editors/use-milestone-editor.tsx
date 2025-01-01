import {testIdProps} from '@github-ui/test-id-props'
import {MilestoneIcon} from '@primer/octicons-react'
import {type ActionListItemProps as ItemProps, Octicon} from '@primer/react/deprecated'
import {useCallback} from 'react'

import {MemexColumnDataType} from '../../api/columns/contracts/memex-column'
import {MilestoneState} from '../../api/common-contracts'
import type {SuggestedMilestone} from '../../api/memex-items/contracts'
import {milestoneDueText} from '../../helpers/milestone-due-text'
import type {MemexItemModel} from '../../models/memex-item-model'
import {useFetchSuggestedMilestones} from '../../state-providers/suggestions/use-fetch-suggested-milestones'
import {useUpdateItem} from '../use-update-item'
import styles from './use-milestone-editor.module.css'

export const getTitle = (option: SuggestedMilestone) => {
  return option.title
}

export const convertOptionToItem = (option: SuggestedMilestone): ItemProps & SuggestedMilestone => {
  const isOpenMilestone = option.state === MilestoneState.Open
  return {
    ...option,
    leadingVisual() {
      return (
        <Octicon
          icon={MilestoneIcon}
          aria-label={isOpenMilestone ? 'Open milestone' : 'Closed milestone'}
          className={styles.Octicon}
        />
      )
    },
    text: option.title,
    description: milestoneDueText(option),
    descriptionVariant: 'block',
    groupId: isOpenMilestone ? 'open' : 'closed',
    ...testIdProps('table-cell-editor-row'),
  }
}

type UseMilestoneEditorProps = {
  model: MemexItemModel
  onSaved?: () => void
}

export function useMilestoneEditor({model, onSaved}: UseMilestoneEditorProps) {
  const {updateItem} = useUpdateItem()
  const {fetchSuggestedMilestones} = useFetchSuggestedMilestones()

  const fetchOptions = useCallback(() => {
    fetchSuggestedMilestones(model)
  }, [model, fetchSuggestedMilestones])

  const saveSelected = useCallback(
    async (nextSelected: Array<SuggestedMilestone>) => {
      await updateItem(model, {
        dataType: MemexColumnDataType.Milestone,
        value: nextSelected[0],
      })
      if (onSaved) {
        onSaved()
      }
    },
    [model, onSaved, updateItem],
  )

  return {
    fetchOptions,
    saveSelected,
  }
}
