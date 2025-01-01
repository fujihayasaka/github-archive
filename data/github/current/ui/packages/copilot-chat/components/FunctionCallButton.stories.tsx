import {Box} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import type React from 'react'

import type {WebSearchResultReference} from '../utils/copilot-chat-types'
import type {BingGroundingFunctionButton} from './FunctionCallButton'
import {BingFunctionButton, CodeSearchButton} from './FunctionCallButton'

type PropsOf<T> = T extends React.ComponentType<infer P> ? P : never
type BingFunctionButtonProps = PropsOf<typeof BingFunctionButton>
type BingGroundingFunctionButtonProps = PropsOf<typeof BingGroundingFunctionButton>
type CodeSearchButtonProps = PropsOf<typeof CodeSearchButton>

const meta = {
  title: 'Apps/Copilot/FunctionCallButton',
  component: BingFunctionButton,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof BingFunctionButton>

export default meta

const Wrapper = ({children}: {children?: React.ReactNode | undefined}) => <Box sx={{width: '400px'}}>{children}</Box>

export const WebSearch: StoryObj<BingFunctionButtonProps> = {
  args: {
    functionCall: {
      slug: 'bing-search',
      status: 'completed',
      arguments: '{\n  "query": "latest release of Ruby on Rails"\n}',
      references: [
        {
          query: 'latest release of Ruby on Rails',
          results: [
            {
              title: 'Ruby on Rails — Releases',
              excerpt:
                "So, following the script We are releasing a new release candidate, Rails 3.2.14.rc2. If no regressions are found we will... July 12, 2013 [ANN] Rails 3.2.14.rc1 has been released! ... We've released Ruby on Rails 2.3.6: six months of bug fixes, a handful of new features, and a strong bridge to Rails 3. We deprecated some obscure and ancient ...",
              url: 'https://rubyonrails.org/category/releases',
            } as WebSearchResultReference,
            {
              title: 'Ruby on Rails — A web-app framework that includes everything needed to ...',
              excerpt:
                "Ruby on Rails scales from HELLO WORLD to IPO. Rails 7.1.3.2 — released February 21, 2024. You're in good company. ... The latest releases and updates on development. Learn more about Hotwire, the default front-end framework for Rails. Stay up to date with Rails on Twitter, ...",
              url: 'https://rubyonrails.org/',
            } as WebSearchResultReference,
            {
              title: 'Ruby on Rails | A web-application framework that includes everything ...',
              excerpt:
                "Latest version — Rails 6.1.4.1 released August 19, 2021. Released August 19, 2021. You've probably already used many of the applications that were built with Ruby on Rails: Basecamp, HEY, GitHub, ... but there are literally hundreds of thousands of applications built with the framework since its release in 2004. Ruby on Rails is open source ...",
              url: 'https://rails.github.io/homepage/',
            } as WebSearchResultReference,
            {
              title: 'Ruby on Rails — Rails 7.0: Fulfilling a vision',
              excerpt:
                "Rails 7.0: Fulfilling a vision. Posted by dhh. This version of Rails has been years in the conceptual making. It's the fulfillment of a vision to present a truly full-stack approach to web development that tackles both the front- and back-end challenges with equal vigor. An omakase menu that includes everything from the aperitif to the dessert.",
              url: 'https://rubyonrails.org/2021/12/15/Rails-7-fulfilling-a-vision',
            } as WebSearchResultReference,
            {
              title: 'Rails Contributors - Rails Releases - Ruby on Rails',
              excerpt:
                'Listing of Ruby on Rails releases. Rails Releases Showing 304 releases. Tag Date Release Contributors Commits; v7.1.3.2: 21 Feb 2024',
              url: 'https://www.rubyonrails.org/releases',
            } as WebSearchResultReference,
          ],
          // eslint-disable-next-line camelcase
          agent_response: {type: 'text', text: {value: '', annotations: []}, bing_searches: []},
          status: 'success',
          type: 'web-search',
        },
      ],
    },
    skillArgs: {
      kind: 'bing-search',
      query: 'latest release of Ruby on Rails',
    },
  },
  render: (args: BingFunctionButtonProps) => (
    <Wrapper>
      <BingFunctionButton {...args} />
    </Wrapper>
  ),
}

export const WebSearchInProgress: StoryObj<BingFunctionButtonProps> = {
  args: {
    functionCall: {
      slug: 'bing-search',
      status: 'started',
      arguments: '{\n  "query": "latest release of Ruby on Rails"\n}',
      references: [],
    },
    skillArgs: {
      kind: 'bing-search',
      query: 'latest release of Ruby on Rails',
    },
  },
  render: (args: BingFunctionButtonProps) => (
    <Wrapper>
      <BingFunctionButton {...args} />
    </Wrapper>
  ),
}

export const WebSearchWithGrounding: StoryObj<BingGroundingFunctionButtonProps> = {
  args: {
    functionCall: {
      slug: 'bing-search',
      status: 'completed',
      arguments: '{\n  "query": "latest release of Ruby on Rails"\n}',
      references: [
        {
          query: 'latest release of Ruby on Rails',
          results: [
            {
              title: 'Ruby on Rails — Releases',
              excerpt: '',
              url: 'https://rubyonrails.org/category/releases',
            } as WebSearchResultReference,
            {
              title: 'Rails Contributors - Rails Releases - Ruby on Rails',
              excerpt:
                'Listing of Ruby on Rails releases. Rails Releases Showing 304 releases. Tag Date Release Contributors Commits; v7.1.3.2: 21 Feb 2024',
              url: 'https://www.rubyonrails.org/releases',
            } as WebSearchResultReference,
          ],
          // eslint-disable-next-line camelcase
          agent_response: {
            type: 'text',
            text: {
              value: 'The latest release of Ruby on Rails in version 7.1.3.2',
              annotations: [
                {
                  type: 'text',
                  text: '[1†source]',
                  // eslint-disable-next-line camelcase
                  start_index: 10,
                  // eslint-disable-next-line camelcase
                  end_index: 15,
                  // eslint-disable-next-line camelcase
                  url_citation: {
                    title: 'Rails Contributors - Rails Releases - Ruby on Rails',
                    url: 'https://www.rubyonrails.org/releases',
                  },
                },
              ],
            },
            // eslint-disable-next-line camelcase
            bing_searches: [
              {
                text: 'latest release of Ruby on Rails',
                url: 'https://www.bing.com/search?q=latest+release+of+ruby+on+rails',
              },
            ],
          },
          status: 'success',
          type: 'web-search',
        },
      ],
    },
    skillArgs: {
      kind: 'bing-search',
      query: 'latest release of Ruby on Rails',
    },
  },
  render: (args: BingFunctionButtonProps) => (
    <Wrapper>
      <BingFunctionButton {...args} />
    </Wrapper>
  ),
}

export const WebSearchWithGroundingInProgress: StoryObj<BingGroundingFunctionButtonProps> = {
  args: {
    functionCall: {
      slug: 'bing-search',
      status: 'started',
      arguments: '{\n  "query": "latest release of Ruby on Rails"\n}',
      references: [],
    },
    skillArgs: {
      kind: 'bing-search',
      query: 'latest release of Ruby on Rails',
    },
  },
  render: (args: BingFunctionButtonProps) => (
    <Wrapper>
      <BingFunctionButton {...args} />
    </Wrapper>
  ),
}

export const CodeSearch: StoryObj<CodeSearchButtonProps> = {
  args: {
    functionCall: {
      slug: 'codesearch',
      status: 'completed',
      arguments: '{\n  "query": "list of reserved usernames",\n  "scopingQuery": "repo:github/github"\n}',
      references: [
        {
          type: 'snippet',
          ref: 'refs/heads/master',
          repoID: 3,
          repoName: 'github',
          repoOwner: 'github',
          url: 'https://github.com/github/github/blob/4155ea68824b691d6c90dbb25afcaceecc5b1bef/app/helpers/reactions_helper.rb#L1-L51',
          path: 'app/helpers/reactions_helper.rb',
          commitOID: '4155ea68824b691d6c90dbb25afcaceecc5b1bef',
          languageName: 'Ruby',
          languageID: 326,
          range: {
            start: 1,
            end: 51,
          },
        },
        {
          type: 'snippet',
          ref: 'refs/heads/master',
          repoID: 3,
          repoName: 'github',
          repoOwner: 'github',
          url: 'https://github.com/github/github/blob/4155ea68824b691d6c90dbb25afcaceecc5b1bef/script/seeds/runners/sponsors.rb#L475-L551',
          path: 'script/seeds/runners/sponsors.rb',
          commitOID: '4155ea68824b691d6c90dbb25afcaceecc5b1bef',
          languageName: 'Ruby',
          languageID: 326,
          range: {
            start: 475,
            end: 551,
          },
        },
        {
          type: 'snippet',
          ref: 'refs/heads/master',
          repoID: 3,
          repoName: 'github',
          repoOwner: 'github',
          url: 'https://github.com/github/github/blob/4155ea68824b691d6c90dbb25afcaceecc5b1bef/config/initializers/denylist.rb#L1-L189',
          path: 'config/initializers/denylist.rb',
          commitOID: '4155ea68824b691d6c90dbb25afcaceecc5b1bef',
          languageName: 'Ruby',
          languageID: 326,
          range: {
            start: 1,
            end: 189,
          },
        },
        {
          type: 'snippet',
          ref: 'refs/heads/master',
          repoID: 3,
          repoName: 'github',
          repoOwner: 'github',
          url: 'https://github.com/github/github/blob/4155ea68824b691d6c90dbb25afcaceecc5b1bef/lib/github/database_structure.rb#L194-L322',
          path: 'lib/github/database_structure.rb',
          commitOID: '4155ea68824b691d6c90dbb25afcaceecc5b1bef',
          languageName: 'Ruby',
          languageID: 326,
          range: {
            start: 194,
            end: 322,
          },
        },
        {
          type: 'snippet',
          ref: 'refs/heads/master',
          repoID: 3,
          repoName: 'github',
          repoOwner: 'github',
          url: 'https://github.com/github/github/blob/4155ea68824b691d6c90dbb25afcaceecc5b1bef/app/helpers/suggested_usernames_helper.rb#L37-L156',
          path: 'app/helpers/suggested_usernames_helper.rb',
          commitOID: '4155ea68824b691d6c90dbb25afcaceecc5b1bef',
          languageName: 'Ruby',
          languageID: 326,
          range: {
            start: 37,
            end: 156,
          },
        },
        {
          type: 'snippet',
          ref: 'refs/heads/master',
          repoID: 3,
          repoName: 'github',
          repoOwner: 'github',
          url: 'https://github.com/github/github/blob/4155ea68824b691d6c90dbb25afcaceecc5b1bef/packages/community_and_safety/test/models/reserved_login_test.rb#L161-L246',
          path: 'packages/community_and_safety/test/models/reserved_login_test.rb',
          commitOID: '4155ea68824b691d6c90dbb25afcaceecc5b1bef',
          languageName: 'Ruby',
          languageID: 326,
          range: {
            start: 161,
            end: 246,
          },
        },
      ],
    },
    skillArgs: {
      kind: 'lexical-code-search',
      query: 'list of reserved usernames',
      scopingQuery: 'repo:github/github',
    },
  },
  render: (args: CodeSearchButtonProps) => (
    <Wrapper>
      <CodeSearchButton {...args} />
    </Wrapper>
  ),
}

export const LexicalSearchInProgress: StoryObj<CodeSearchButtonProps> = {
  args: {
    functionCall: {
      slug: 'lexical-code-search',
      status: 'started',
      arguments: '{\n  "query": "list of reserved usernames",\n  "scopingQuery": "repo:github/github"\n}',
      references: [],
    },
    skillArgs: {
      kind: 'lexical-code-search',
      query: 'list of reserved usernames',
      scopingQuery: 'repo:github/github',
    },
  },
  render: (args: CodeSearchButtonProps) => (
    <Wrapper>
      <CodeSearchButton {...args} />
    </Wrapper>
  ),
}
