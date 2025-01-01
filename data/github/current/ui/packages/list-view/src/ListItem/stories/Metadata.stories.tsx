import {CopyIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import {type PropsWithChildren, useMemo} from 'react'

import {ListView} from '../../ListView/ListView'
import {Comments, generateLabels, generateTitle, Labels} from '../../ListView/stories/helpers'
import {ListItem} from '../ListItem'
import {ListItemMetadata} from '../Metadata'
import {ListItemTitle} from '../Title'
import styles from './Metadata.stories.module.css'

const meta: Meta<PropsWithChildren> = {
  title: 'Recipes/ListView/ListItem/Metadata',
  component: ListItemMetadata,
}

export default meta
type Story = StoryObj<PropsWithChildren>

export const Example: Story = {
  name: 'Metadata',
  render: () => {
    return (
      <>
        {[0, 1, 2].map(index => {
          const title = useMemo(() => generateTitle('Issues', index), [index])
          return (
            <ListItem
              key={index}
              title={<ListItemTitle value={title!} />}
              metadata={
                <>
                  <ListItemMetadata className={styles.ListItemMetadata_0}>
                    <Labels items={generateLabels(index)} />
                  </ListItemMetadata>
                  <ListItemMetadata>
                    <Comments count={index * 2} />
                  </ListItemMetadata>
                  <ListItemMetadata>
                    <IconButton icon={CopyIcon} variant="invisible" aria-label="Copy" />
                  </ListItemMetadata>
                </>
              }
            />
          )
        })}
      </>
    )
  },
  decorators: [
    Story => (
      <ListView title="Metadata list">
        <Story />
      </ListView>
    ),
  ],
}
