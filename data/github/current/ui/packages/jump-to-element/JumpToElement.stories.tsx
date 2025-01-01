import type {Meta} from '@storybook/react'
import {clsx} from 'clsx'
import {HttpResponse, http} from 'msw'

const meta = {
  title: 'Apps/Global Nav/JumpToElement',
  component: JumpToSearch,
  parameters: {
    msw: {
      handlers: [http.post(`/_graphql/GetSuggestedNavigationDestinations`, async () => HttpResponse.json(suggestions))],
    },
  },
} satisfies Meta<typeof JumpToSearch>

export default meta

export const Example = {}

function JumpToSuggestion({className}: {className?: string}) {
  return (
    <li
      className={clsx(
        'd-flex flex-justify-start flex-items-center p-0 f5 navigation-item js-navigation-item',
        className,
      )}
      role="option"
      aria-selected="false"
    >
      <a
        data-action="click:jump-to#handleSuggestionClick"
        tabIndex={-1}
        className="no-underline d-flex flex-auto flex-items-center jump-to-suggestions-path js-jump-to-suggestion-path js-navigation-open p-2"
        href="placeholder"
        data-item-type="suggestion"
      >
        <div className="jump-to-octicon js-jump-to-octicon flex-shrink-0 mr-2 text-center d-none">
          <svg
            aria-label="Repository"
            role="img"
            height="16"
            viewBox="0 0 16 16"
            version="1.1"
            width="16"
            data-view-component="true"
            className="octicon octicon-repo js-jump-to-octicon-repo d-none flex-shrink-0"
          >
            <path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z" />
          </svg>
          <svg
            aria-label="Project"
            role="img"
            height="16"
            viewBox="0 0 16 16"
            version="1.1"
            width="16"
            data-view-component="true"
            className="octicon octicon-project js-jump-to-octicon-project d-none flex-shrink-0"
          >
            <path d="M1.75 0h12.5C15.216 0 16 .784 16 1.75v12.5A1.75 1.75 0 0 1 14.25 16H1.75A1.75 1.75 0 0 1 0 14.25V1.75C0 .784.784 0 1.75 0ZM1.5 1.75v12.5c0 .138.112.25.25.25h12.5a.25.25 0 0 0 .25-.25V1.75a.25.25 0 0 0-.25-.25H1.75a.25.25 0 0 0-.25.25ZM11.75 3a.75.75 0 0 1 .75.75v7.5a.75.75 0 0 1-1.5 0v-7.5a.75.75 0 0 1 .75-.75Zm-8.25.75a.75.75 0 0 1 1.5 0v5.5a.75.75 0 0 1-1.5 0ZM8 3a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 3Z" />
          </svg>
          <svg
            aria-label="Search"
            role="img"
            height="16"
            viewBox="0 0 16 16"
            version="1.1"
            width="16"
            data-view-component="true"
            className="octicon octicon-search js-jump-to-octicon-search d-none flex-shrink-0"
          >
            <path d="M10.68 11.74a6 6 0 0 1-7.922-8.982 6 6 0 0 1 8.982 7.922l3.04 3.04a.749.749 0 0 1-.326 1.275.749.749 0 0 1-.734-.215ZM11.5 7a4.499 4.499 0 1 0-8.997 0A4.499 4.499 0 0 0 11.5 7Z" />
          </svg>
        </div>

        <img
          className="avatar mr-2 flex-shrink-0 js-jump-to-suggestion-avatar d-none"
          alt=""
          role="img"
          aria-label="Team"
          src=""
          width="28"
          height="28"
        />

        <div className="jump-to-suggestion-name js-jump-to-suggestion-name flex-auto overflow-hidden text-left no-wrap css-truncate css-truncate-target" />

        <div className="border rounded-2 flex-shrink-0 color-bg-subtle px-1 color-fg-muted ml-1 f6 d-none js-jump-to-badge-search">
          <span className="js-jump-to-badge-search-text-default d-none">Search</span>
          <span className="js-jump-to-badge-search-text-global d-none">All GitHub</span>
          <span aria-hidden="true" className="d-inline-block ml-1 v-align-middle">
            ↵
          </span>
        </div>

        <div
          aria-hidden="true"
          className="border rounded-2 flex-shrink-0 color-bg-subtle px-1 color-fg-muted ml-1 f6 d-none d-on-nav-focus js-jump-to-badge-jump"
        >
          Jump to
          <span className="d-inline-block ml-1 v-align-middle">↵</span>
        </div>
      </a>
    </li>
  )
}

function JumpToSearch() {
  return (
    <jump-to>
      <div className="js-site-search">
        <form
          data-target="jump-to.form"
          data-action="
            focusin:jump-to#handleFocusIn
            focusout:jump-to#handleFocusOut
            submit:jump-to#handleSubmit
            navigation:keydown:jump-to#handleNavigationKeydown
            navigation:focus:jump-to#handleNavigationFocus"
          className="js-site-search-form"
          role="search"
          aria-label="Site"
          data-unscoped-search-url="/search"
          data-turbo="false"
          action="/search"
          acceptCharset="UTF-8"
          method="get"
        >
          <label htmlFor="AppHeader-searchInput">Search</label>{' '}
          <input
            data-target="jump-to.field"
            data-action="input:jump-to#handleInput"
            id="AppHeader-searchInput"
            type="search"
            placeholder="Search or jump to…"
            className="jump-to-field js-site-search-focus"
            name="q"
            data-unscoped-placeholder="Search or jump to…"
            data-scoped-placeholder="Search or jump to…"
            autoCapitalize="off"
            role="combobox"
            aria-haspopup="listbox"
            aria-expanded="false"
            aria-autocomplete="list"
            aria-controls="jump-to-results"
            aria-label="Search or jump to…"
            data-jump-to-suggestions-path="/_graphql/GetSuggestedNavigationDestinations"
            spellCheck="false"
            autoComplete="off"
          />
          <input type="hidden" value="_DEADBEEF" data-target="jump-to.csrfTokenInput" data-csrf="true" />
          <input type="hidden" className="js-site-search-type-field" name="type" />
          <div data-target="jump-to.suggestionsContainer" className="jump-to-suggestions d-none">
            <ul data-target="jump-to.suggestionsTemplate" className="d-none">
              <JumpToSuggestion className="js-jump-to-suggestion" />
            </ul>

            <ul data-target="jump-to.noResultsTemplate" className="d-none">
              <li className="d-flex flex-justify-center flex-items-center f5 d-none js-jump-to-suggestion p-2">
                <span className="color-fg-muted">No suggested jump to results</span>
              </li>
            </ul>

            <ul
              id="jump-to-results"
              role="listbox"
              data-target="jump-to.resultsContainer"
              className="p-0 m-0 js-navigation-container jump-to-suggestions-results-container js-active-navigation-container"
            >
              <JumpToSuggestion className="js-jump-to-scoped-search d-none" />
              <JumpToSuggestion className="js-jump-to-owner-scoped-search d-none" />
              <JumpToSuggestion className="js-jump-to-global-search d-none" />
            </ul>
          </div>
        </form>
      </div>
    </jump-to>
  )
}

const suggestions = {
  data: {
    suggestions: {
      nodes: [
        {
          type: 'Repository',
          databaseId: 305811857,
          name: 'github/web-systems',
          path: '/github/web-systems',
        },
        {
          type: 'Repository',
          databaseId: 3,
          name: 'github/github',
          path: '/github/github',
        },
        {
          type: 'Repository',
          databaseId: 277573683,
          name: 'github/elasticsearch',
          path: '/github/elasticsearch',
        },
        {
          type: 'Repository',
          databaseId: 165670309,
          name: 'TanStack/router',
          path: '/TanStack/router',
        },
        {
          type: 'Repository',
          databaseId: 537167173,
          name: 'remix-run/examples',
          path: '/remix-run/examples',
        },
        {
          type: 'Repository',
          databaseId: 65794292,
          name: 'styled-components/styled-components',
          path: '/styled-components/styled-components',
        },
        {
          type: 'Repository',
          databaseId: 834166489,
          name: 'github/hummingbird',
          path: '/github/hummingbird',
        },
        {
          type: 'Repository',
          databaseId: 836390744,
          name: 'github/react-platform',
          path: '/github/react-platform',
        },
        {
          type: 'Repository',
          databaseId: 688441777,
          name: 'github/heaven-gates',
          path: '/github/heaven-gates',
        },
        {
          type: 'Repository',
          databaseId: 66661784,
          name: 'github/datadog-monitoring',
          path: '/github/datadog-monitoring',
        },
        {
          type: 'Repository',
          databaseId: 121814210,
          name: 'primer/react',
          path: '/primer/react',
        },
        {
          type: 'Repository',
          databaseId: 567883367,
          name: 'github/monolith-fitness',
          path: '/github/monolith-fitness',
        },
        {
          type: 'Repository',
          databaseId: 551089638,
          name: 'github/core-ux',
          path: '/github/core-ux',
        },
        {
          type: 'Repository',
          databaseId: 454103999,
          name: 'github/core-productivity',
          path: '/github/core-productivity',
        },
        {
          type: 'Repository',
          databaseId: 791987828,
          name: 'github/data-center-runway',
          path: '/github/data-center-runway',
        },
        {
          type: 'Repository',
          databaseId: 253831084,
          name: 'github/blackbird',
          path: '/github/blackbird',
        },
        {
          type: 'Repository',
          databaseId: 55853446,
          name: 'mxstbr/ama',
          path: '/mxstbr/ama',
        },
        {
          type: 'Repository',
          databaseId: 681756577,
          name: 'keithamus/invokers-polyfill',
          path: '/keithamus/invokers-polyfill',
        },
        {
          type: 'Repository',
          databaseId: 11969507,
          name: 'whatwg/html',
          path: '/whatwg/html',
        },
        {
          type: 'Repository',
          databaseId: 5443950,
          name: 'github/education',
          path: '/github/education',
        },
        {
          type: 'Repository',
          databaseId: 644798806,
          name: 'github/incident-lifecycle',
          path: '/github/incident-lifecycle',
        },
        {
          type: 'Repository',
          databaseId: 245304009,
          name: 'github/canada',
          path: '/github/canada',
        },
        {
          type: 'Repository',
          databaseId: 174568303,
          name: 'github/pull-requests',
          path: '/github/pull-requests',
        },
        {
          type: 'Repository',
          databaseId: 77558539,
          name: 'github/security-grc-reviews',
          path: '/github/security-grc-reviews',
        },
        {
          type: 'Repository',
          databaseId: 98946937,
          name: 'github/issues',
          path: '/github/issues',
        },
        {
          type: 'Repository',
          databaseId: 643832736,
          name: 'github/performance-engineering',
          path: '/github/performance-engineering',
        },
        {
          type: 'Repository',
          databaseId: 237189930,
          name: 'playwright-community/jest-playwright',
          path: '/playwright-community/jest-playwright',
        },
        {
          type: 'Repository',
          databaseId: 691651590,
          name: 'piratetaco/storybook-test-runner',
          path: '/piratetaco/storybook-test-runner',
        },
        {
          type: 'Repository',
          databaseId: 534767064,
          name: 'github/monolith-platform',
          path: '/github/monolith-platform',
        },
        {
          type: 'Repository',
          databaseId: 40465073,
          name: 'github/accessibility',
          path: '/github/accessibility',
        },
        {
          type: 'Repository',
          databaseId: 276207736,
          name: 'github/primer',
          path: '/github/primer',
        },
        {
          type: 'Repository',
          databaseId: 595344747,
          name: 'github/EDR',
          path: '/github/EDR',
        },
        {
          type: 'Repository',
          databaseId: 208883147,
          name: 'github/ghes',
          path: '/github/ghes',
        },
        {
          type: 'Repository',
          databaseId: 245519314,
          name: 'github/thehub',
          path: '/github/thehub',
        },
        {
          type: 'Repository',
          databaseId: 1451352,
          name: 'mochajs/mocha',
          path: '/mochajs/mocha',
        },
        {
          type: 'Repository',
          databaseId: 1441878,
          name: 'github/ci',
          path: '/github/ci',
        },
        {
          type: 'Repository',
          databaseId: 361963648,
          name: 'github/devsat',
          path: '/github/devsat',
        },
        {
          type: 'Repository',
          databaseId: 645588772,
          name: 'github/gh-tpm',
          path: '/github/gh-tpm',
        },
        {
          type: 'Repository',
          databaseId: 486404007,
          name: 'github/release-controller',
          path: '/github/release-controller',
        },
        {
          type: 'Repository',
          databaseId: 17000439,
          name: 'github/enterprise-releases',
          path: '/github/enterprise-releases',
        },
        {
          type: 'Repository',
          databaseId: 536324275,
          name: 'github/alloy',
          path: '/github/alloy',
        },
        {
          type: 'Repository',
          databaseId: 212897430,
          name: 'github/discussions',
          path: '/github/discussions',
        },
        {
          type: 'Repository',
          databaseId: 488514,
          name: 'rubygems/bundler',
          path: '/rubygems/bundler',
        },
        {
          type: 'Repository',
          databaseId: 136959794,
          name: 'github/failbot-js',
          path: '/github/failbot-js',
        },
        {
          type: 'Repository',
          databaseId: 516560962,
          name: '7nohe/openapi-react-query-codegen',
          path: '/7nohe/openapi-react-query-codegen',
        },
        {
          type: 'Repository',
          databaseId: 286859940,
          name: 'github/compute-images',
          path: '/github/compute-images',
        },
        {
          type: 'Repository',
          databaseId: 90796663,
          name: 'puppeteer/puppeteer',
          path: '/puppeteer/puppeteer',
        },
        {
          type: 'Repository',
          databaseId: 611927574,
          name: 'github/turbo',
          path: '/github/turbo',
        },
        {
          type: 'Repository',
          databaseId: 18689107,
          name: 'github/gitcoin',
          path: '/github/gitcoin',
        },
        {
          type: 'Repository',
          databaseId: 24663344,
          name: 'github/include-fragment-element',
          path: '/github/include-fragment-element',
        },
        {
          type: 'Repository',
          databaseId: 786898248,
          name: 'github/accessibility-audit-guide',
          path: '/github/accessibility-audit-guide',
        },
        {
          type: 'Repository',
          databaseId: 84238782,
          name: 'sapegin/jest-cheat-sheet',
          path: '/sapegin/jest-cheat-sheet',
        },
        {
          type: 'Repository',
          databaseId: 20929025,
          name: 'microsoft/TypeScript',
          path: '/microsoft/TypeScript',
        },
        {
          type: 'Repository',
          databaseId: 765607228,
          name: 'ubiquity/rpc-handler',
          path: '/ubiquity/rpc-handler',
        },
        {
          type: 'Repository',
          databaseId: 108313282,
          name: 'github/vuln-mgmt',
          path: '/github/vuln-mgmt',
        },
        {
          type: 'Repository',
          databaseId: 245268140,
          name: 'ndeadly/MissionControl',
          path: '/ndeadly/MissionControl',
        },
        {
          type: 'Repository',
          databaseId: 842092537,
          name: 'github/endpoint-software-remediation',
          path: '/github/endpoint-software-remediation',
        },
        {
          type: 'Repository',
          databaseId: 446831156,
          name: 'github/test-frameworks',
          path: '/github/test-frameworks',
        },
      ],
    },
  },
}
