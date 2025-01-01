import {graphql, useFragment} from 'react-relay'
import {testIdProps} from '@github-ui/test-id-props'
import type {DiscussionCategoryPickerDiscussionCategories$key} from './__generated__/DiscussionCategoryPickerDiscussionCategories.graphql'
import {Select} from '@primer/react'
import {useCallback, useEffect} from 'react'

export type DiscussionCategoryPickerProps = {
  onSelect: (category: string) => void
  discussionCategoriesData: DiscussionCategoryPickerDiscussionCategories$key
  categoryId?: string
}

export const DiscussionCategoriesFragment = graphql`
  fragment DiscussionCategoryPickerDiscussionCategories on Repository {
    discussionCategories(first: $first, filterByAssignable: true) {
      edges {
        node {
          id
          name
        }
      }
    }
  }
`

export function DiscussionCategoryPicker({discussionCategoriesData, ...rest}: DiscussionCategoryPickerProps) {
  return discussionCategoriesData ? (
    <DiscussionCategoryPickerInternal {...rest} discussionCategoriesData={discussionCategoriesData} />
  ) : null
}

export function DiscussionCategoryPickerInternal({
  discussionCategoriesData,
  onSelect,
  categoryId,
}: DiscussionCategoryPickerProps) {
  const onChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    onSelect(e.currentTarget.value)
  }

  const {discussionCategories} = useFragment(DiscussionCategoriesFragment, discussionCategoriesData)

  useEffect(() => {
    const firstCategory = discussionCategories?.edges?.[0]?.node?.id
    if (firstCategory) {
      onSelect(firstCategory)
    }
  }, [discussionCategories, onSelect])

  const renderOptions = useCallback(() => {
    if (!discussionCategories.edges) {
      return null
    }

    return discussionCategories.edges.map((category, index) => {
      if (!category || !category.node) {
        return null
      }

      return (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <Select.Option key={index} value={category.node.id}>
          {category.node.name}
        </Select.Option>
      )
    })
  }, [discussionCategories])

  return (
    <Select id={categoryId} block onChange={onChange} {...testIdProps('select')}>
      {renderOptions()}
    </Select>
  )
}
