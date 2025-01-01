import {ActionList, ActionMenu, IconButton, Stack} from '@primer/react'
import {KebabHorizontalIcon, MarkGithubIcon} from '@primer/octicons-react'
import {ResourceCard} from './ResourceCard/ResourceCard'
import {useState} from 'react'
import styles from './NuxDashboardDocs.module.css'
import {updateSetting} from '../../helpers/settings-helper'
import {DashboardDismissalSettings} from '../../constants/dashboard-settings'
import {useClickAnalytics} from '@github-ui/use-analytics'

interface NuxDashboardDocsProps {
  heading: string
  dismissed: boolean
}

const resourceCards = [
  {
    // the default icon is the book icon, we are overwriting it here
    icon: <MarkGithubIcon size={24} />,
    title: 'GitHub Documentation',
    description: 'Help for wherever you are on your journey',
    href: 'https://docs.github.com/',
  },
  {
    title: 'About GitHub and Git',
    readTime: 2,
    href: 'https://docs.github.com/en/get-started/start-your-journey/about-github-and-git',
  },
  {
    title: 'How to create your first repository',
    readTime: 5,
    href: 'https://docs.github.com/repositories/creating-and-managing-repositories/quickstart-for-repositories',
  },
  {
    title: 'Creating a pull request',
    readTime: 6,
    href: 'https://docs.github.com/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request',
  },
  {
    title: 'What is GitHub Copilot?',
    readTime: 6,
    href: 'https://docs.github.com/copilot/about-github-copilot/what-is-github-copilot',
  },
  {
    title: 'GitHub flow',
    readTime: 4,
    href: 'https://docs.github.com/get-started/using-github/github-flow',
  },
  {
    title: 'Hello World exercise',
    readTime: 6,
    href: 'https://docs.github.com/get-started/start-your-journey/hello-world',
  },
  {
    title: 'Copilot Chat Cookbook',
    readTime: 2,
    href: 'https://docs.github.com/copilot/copilot-chat-cookbook',
  },
]

export const NuxDashboardDocs = ({heading, dismissed}: NuxDashboardDocsProps) => {
  const [isDismissed, setIsDismissed] = useState<boolean>(dismissed)

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const handleDismiss = () => {
    setIsDismissed(true)
    updateSetting(DashboardDismissalSettings.Docs, true)

    sendClickAnalyticsEvent({
      category: 'zero_user_dashboard',
      action: 'click.docs.dismiss',
    })
  }

  return isDismissed ? null : (
    <section aria-labelledby="resources-heading" data-testid="docs-section">
      <Stack direction="vertical" gap="normal" className="mb-3">
        <Stack direction="horizontal" justify="space-between" align="center">
          <h2 id="resources-heading" className="f5">
            {heading}
          </h2>
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton
                icon={KebabHorizontalIcon}
                aria-label="Remove section"
                variant="invisible"
                data-testid="docs-options"
              />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay align="end">
              <ActionList>
                <ActionList.LinkItem onClick={handleDismiss} data-testid="docs-remove-option">
                  Remove from dashboard
                </ActionList.LinkItem>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </Stack>
        <ul className={styles.grid}>
          {resourceCards.map(card => (
            <li key={card.title}>
              <ResourceCard {...card} />
            </li>
          ))}
        </ul>
      </Stack>
    </section>
  )
}

export default NuxDashboardDocs
