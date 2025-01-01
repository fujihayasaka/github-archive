import type {Meta, StoryObj} from '@storybook/react'
import {useMemo} from 'react'

import {ListView} from '../../ListView/ListView'
import {generateDescription, generateTitle} from '../../ListView/stories/helpers'
import {ListItemDescription} from '../Description'
import {ListItemDescriptionItem} from '../DescriptionItem'
import {ListItem} from '../ListItem'
import {ListItemMainContent} from '../MainContent'
import {ListItemTitle} from '../Title'

const meta: Meta = {
  title: 'Recipes/ListView/ListItem/DescriptionItem',
  component: ListItemDescriptionItem,
}

export default meta

export const Example: StoryObj = {
  name: 'DescriptionItem',
  render: () => {
    return (
      <>
        {[0, 1, 2].map(index => {
          const title = useMemo(() => generateTitle('Issues', index), [index])
          const description = useMemo(() => generateDescription('Branch name'), [])

          return (
            <ListItem key={index} title={<ListItemTitle value={title!} />}>
              <ListItemMainContent>
                <ListItemDescription style={{width: '100%'}}>
                  <ListItemDescriptionItem>{description}</ListItemDescriptionItem>
                  <ListItemDescriptionItem>second description</ListItemDescriptionItem>
                  <ListItemDescriptionItem>third description</ListItemDescriptionItem>
                </ListItemDescription>
              </ListItemMainContent>
            </ListItem>
          )
        })}
      </>
    )
  },
  decorators: [
    Story => (
      <ListView title="DescriptionItem list">
        <Story />
      </ListView>
    ),
  ],
}
