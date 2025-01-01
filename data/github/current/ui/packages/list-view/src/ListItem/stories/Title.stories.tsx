import {type SafeHTMLString, SafeHTMLText} from '@github-ui/safe-html'
import {EllipsisIcon, IssueOpenedIcon} from '@primer/octicons-react'
import {IconButton, Label} from '@primer/react'
import {action} from '@storybook/addon-actions'
import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, within} from '@storybook/test'
import {type ReactNode, useState} from 'react'
import {Link, MemoryRouter, Route, Routes} from 'react-router-dom'

import {Variants} from '../../constants'
import {ListView} from '../../ListView/ListView'
import {generateLabels} from '../../ListView/stories/helpers'
import type {VariantType} from '../../ListView/VariantContext'
import {ListItemDescription} from '../Description'
import {ListItemLeadingContent} from '../LeadingContent'
import {ListItemLeadingVisual} from '../LeadingVisual'
import {ListItem} from '../ListItem'
import {ListItemMainContent} from '../MainContent'
import {ListItemSafeHTMLTitle, ListItemTitle, type ListItemTitleProps} from '../Title'
import styles from './Title.stories.module.css'

type ListItemTitleWithArgs = ListItemTitleProps & {variant: VariantType}

const meta: Meta<ListItemTitleWithArgs> = {
  title: 'Recipes/ListView/ListItem/Title',
  component: ListItemTitle,
  argTypes: {
    variant: {
      description: 'Type of ListView variant. Controls the width and height of the list and its contents',
      options: Variants,
      control: 'radio',
    },
  },
}

export default meta
type Story = StoryObj<ListItemTitleWithArgs>
type SampleListItemProps = {title: SafeHTMLString | string} & Omit<ListItemTitleProps, 'value'>

const SampleListItem = ({title, children, ...titleProps}: SampleListItemProps) => (
  <ListItem
    title={
      <ListItemTitle value={title} {...titleProps}>
        {children}
      </ListItemTitle>
    }
  >
    <ListItemLeadingContent>
      <ListItemLeadingVisual icon={IssueOpenedIcon} color="fg.muted" description="Open Issue" />
    </ListItemLeadingContent>
  </ListItem>
)

export const TitleWithStaticText: Story = {
  args: {
    variant: 'compact',
  },
  render: ({variant, ...args}: ListItemTitleWithArgs) => (
    <ListView title="Static Title list" variant={variant}>
      <SampleListItem {...args} title="I am a non-clickable title!" />
    </ListView>
  ),
}

export const TitleWithLink: Story = {
  args: {
    variant: 'compact',
    href: '#',
  },
  render: ({variant, ...args}: ListItemTitleWithArgs) => (
    <ListView title="Link Title list" variant={variant}>
      <SampleListItem
        {...args}
        onClick={e => {
          e.preventDefault()
          action('on-click')(e)
        }}
        title="I am a clickable title!"
      />
    </ListView>
  ),
}

function ReactRouterWrapper({children}: {children?: ReactNode}) {
  return (
    <MemoryRouter
      initialEntries={['/cats']}
      // eslint-disable-next-line camelcase
      future={{v7_relativeSplatPath: true, v7_startTransition: true}}
    >
      <Routes>
        <Route
          path={'/cats'}
          element={
            <>
              <h2>Cat Page</h2>
              {children}
            </>
          }
        />
        <Route
          path={'/dogs'}
          element={
            <>
              <h2>Dog Page</h2>
              {children}
            </>
          }
        />
      </Routes>
    </MemoryRouter>
  )
}

export const TitleWithReactRouterLink: Story = {
  args: {
    variant: 'compact',
    href: '#',
  },
  render: ({variant, ...args}: ListItemTitleWithArgs) => (
    <ReactRouterWrapper>
      <ListView title="React Router Link Title list" variant={variant}>
        <ListItem
          title={
            <ListItemTitle
              {...args}
              value="I am a clickable title with soft navigation!: Cats"
              linkProps={{as: Link, to: '/cats'}}
            />
          }
        >
          <ListItemLeadingContent>
            <ListItemLeadingVisual icon={IssueOpenedIcon} color="fg.muted" />
          </ListItemLeadingContent>
        </ListItem>
        <ListItem
          title={
            <ListItemTitle
              {...args}
              value="I am a clickable title with soft navigation!: Dogs"
              linkProps={{as: Link, to: '/dogs'}}
            />
          }
        >
          <ListItemLeadingContent>
            <ListItemLeadingVisual icon={IssueOpenedIcon} color="fg.muted" />
          </ListItemLeadingContent>
        </ListItem>
      </ListView>
    </ReactRouterWrapper>
  ),
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const [catLink, dogLink] = canvas.getAllByTestId('listitem-title-link')
    await expect(catLink).toHaveAttribute('href', '/cats')
    await userEvent.click(catLink!)
    await expect(canvas.getByText('Cat Page')).toBeInTheDocument()

    await userEvent.click(dogLink!)
    await expect(dogLink).toHaveAttribute('href', '/dogs')
    await expect(canvas.getByText('Dog Page')).toBeInTheDocument()
  },
}

export const TitleWithSafeHTML: Story = {
  args: {
    variant: 'compact',
  },
  render: ({variant}: {variant: VariantType}) => (
    <ListView title="Markdown Link Title list" variant={variant}>
      <ListItem
        title={
          <ListItemSafeHTMLTitle
            html={
              // eslint-disable-next-line github/unescaped-html-literal
              '<g-emoji class="g-emoji" alias="heart" fallback-src="/images/icons/emoji/unicode/2764.png"><g-emoji class="g-emoji" alias="heart" fallback-src="/images/icons/emoji/unicode/2764.png">❤️</g-emoji></g-emoji>&nbsp;I love emojis in commits'
            }
          />
        }
      >
        <ListItemLeadingContent>
          <ListItemLeadingVisual icon={IssueOpenedIcon} color="fg.muted" description="Open Issue" />
        </ListItemLeadingContent>
      </ListItem>
      <ListItem
        title={
          <ListItemSafeHTMLTitle
            html={
              // eslint-disable-next-line github/unescaped-html-literal
              '<a href="/abc" class="color-fg-default">Merge pull request</a>&nbsp;<a data-hovercard-type="pull_request" href="#">#2</a>&nbsp;<a href="/abc" class="color-fg-default">from repos/monalisa-patch</a>'
            }
          />
        }
      >
        <ListItemLeadingContent>
          <ListItemLeadingVisual icon={IssueOpenedIcon} color="fg.muted" description="Open Issue" />
        </ListItemLeadingContent>
      </ListItem>
      <ListItem
        title={<ListItemSafeHTMLTitle html={'Adding new &lt;svg/&gt; - also i can still respond to onClicks'} />}
      >
        <ListItemLeadingContent>
          <ListItemLeadingVisual icon={IssueOpenedIcon} color="fg.muted" description="Open Issue" />
        </ListItemLeadingContent>
      </ListItem>
    </ListView>
  ),
}

const SampleCommitItem = () => {
  const [showDescription, setShowDescription] = useState(false)
  const shortMessage = 'This is a very long title that showcases an length and longness of a title...'
  const bodyMessageHtml = '...and continues into the commit message body. \n\nThen we have a commit description 🔥'
  return (
    <ListItem
      title={
        <ListItemSafeHTMLTitle html={shortMessage}>
          <IconButton
            size="small"
            icon={EllipsisIcon}
            className={styles.ellipsisButton}
            aria-label="Show description"
            variant="invisible"
            onClick={e => {
              e.preventDefault()
              setShowDescription(!showDescription)
            }}
          />
        </ListItemSafeHTMLTitle>
      }
    >
      <ListItemMainContent>
        {showDescription && bodyMessageHtml && (
          <ListItemDescription>
            <SafeHTMLText html={bodyMessageHtml as SafeHTMLString} className="ws-pre-wrap" />
          </ListItemDescription>
        )}
      </ListItemMainContent>
    </ListItem>
  )
}

export const TitleWithChildren: Story = {
  render: ({variant}: {variant: VariantType}) => {
    return (
      <ListView title="Title with children list" variant={variant}>
        <SampleListItem title="A title can have child elements">
          {generateLabels(4).map(label => (
            <Label key={label.name}>{label.name}</Label>
          ))}
        </SampleListItem>
        <SampleCommitItem />
      </ListView>
    )
  },
}
