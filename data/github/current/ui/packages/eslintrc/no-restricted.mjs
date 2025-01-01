const noRestrictedSyntaxRules = [
  {
    selector: "NewExpression[callee.name='URL'][arguments.length=1]",
    message: 'Please pass in `window.location.origin` as the 2nd argument to `new URL()`',
  },
  {
    selector: "CallExpression[callee.name='unsafeHTML']",
    message: 'Use unsafeHTML sparingly. Please add an eslint-disable comment if you want to use this',
  },
  {
    selector: "CallExpression[callee.name='readInlineData']",
    message:
      'Avoid using readInlineData. Please add an eslint-disable comment if you have to use this. See https://thehub.github.com/support/ecosystem/api-graphql/training/relay/relay-read-inline-data/',
  },
  {
    // @eslint-react/no-children-to-array takes care of `Children.toArray`
    selector:
      "CallExpression[callee.property.name='toArray'][callee.object.name!='Children'][callee.object.property.name!='Children']",
    message: 'Safari does not support .toArray() on iterator objects.',
  },
  {
    // Restrict mocking in test files without restricting import in all files
    selector:
      "CallExpression[callee.object.name='jest'][callee.property.name='mock'][arguments.0.value='@github-ui/verified-fetch']",
    message:
      "Do not use 'jest.mock('@github-ui/verified-fetch')'. Use 'msw' instead. See docs: https://mswjs.io/docs/getting-started.",
  },
]

export function noRestrictedSyntaxRule(additionalRules = []) {
  return {
    'no-restricted-syntax': ['error', ...noRestrictedSyntaxRules, ...additionalRules],
  }
}

const noRestrictedImportsDefaults = {
  paths: [
    {
      name: 'react-dom/test-utils',
      importNames: ['act'],
      message: 'Please use the act from @testing-library/react instead to avoid potential mismatches',
    },
    {
      name: 'react',
      importNames: ['act'],
      message: 'Please use the act from @testing-library/react instead to avoid potential mismatches',
    },
    {
      name: '@github-ui/failbot',
      importNames: ['reportError'],
      message:
        'Calling `reportError` directly is deprecated. To report errors to sentry, let them bubble to the document naturally or re-throw them. If they get caught by calling code you wish to avoid, wrap the re-throw in a setTimeout.',
    },
    {
      name: '@github/selector-observer',
      message:
        'Use a Catalyst component instead of observing an element. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/client-side-behaviors-with-catalyst/',
    },
    {
      name: 'delegated-events',
      message:
        "Use a Catalyst component instead of listening to an element's events. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/client-side-behaviors-with-catalyst/",
    },
    {
      name: '@github/hotkey',
      message: 'Please import from @github-ui/hotkey instead',
    },
    {
      name: '@github/jtml',
      message: 'Use the shimmed version of jtml instead. See @github-ui/jtml-shimmed',
    },
    {
      name: '@primer/react',
      importNames: ['Avatar'],
      message: 'For `Avatar`, use { GitHubAvatar } from @github-ui/github-avatar instead',
    },
    {
      name: '@primer/react/experimental',
      importNames: ['InlineAutocomplete', 'ShowSuggestionsEvent', 'Suggestion'],
      message: 'Use @github-ui/inline-autocomplete instead',
    },
    {
      name: '@primer/react/drafts',
      importNames: ['InlineAutocomplete', 'ShowSuggestionsEvent', 'Suggestion'],
      message: 'Use @github-ui/inline-autocomplete instead',
    },
    {
      name: '@primer/react/experimental',
      importNames: ['MarkdownEditor', 'MarkdownEditorHandle', 'MarkdownEditorProps'],
      message: 'Use @github-ui/comment-box instead',
    },
    {
      name: '@primer/react/drafts',
      importNames: ['MarkdownEditor', 'MarkdownEditorHandle', 'MarkdownEditorProps'],
      message: 'Use @github-ui/comment-box instead',
    },
    {
      name: '@primer/react/experimental',
      importNames: ['MarkdownViewer'],
      message: 'Use { MarkdownViewer } from @github-ui/markdown-viewer instead',
    },
    {
      name: '@primer/react/drafts',
      importNames: ['MarkdownViewer'],
      message: 'Use { MarkdownViewer } from @github-ui/markdown-viewer instead',
    },
    {
      name: 'react',
      importNames: ['useLayoutEffect'],
      message:
        'Please use the `useLayoutEffect` hook from `@github-ui/use-layout-effect` instead. React.useLayoutEffect is not compatible with SSR.',
    },
    {
      name: '@github-ui/toast/ToastContext',
      importNames: ['useToastContext'],
      message:
        'Toasts degrade the overall user experience and are therefore considered a discouraged pattern. Please consider using alternatives as described in: https://www.figma.com/file/yHGQBFKDI3OsRsfx3mMXLn/Expected-a11y-interactions?type=whiteboard&node-id=96-483&t=QSiiBb064ZfsYhy2-4. If you have any questions, reach out in #primer.',
    },
    {
      name: '@testing-library/user-event',
      message:
        'Avoid importing user-event directly. Instead, use `render` (and unpack `user` from the result) or `setupUserEvent` from "@github-ui/react-core/test-utils".',
    },
    {
      name: 'lodash',
      message: 'Use lodash-es instead of lodash',
    },
    {
      name: 'lodash-es',
      message:
        "Don't import the full lodash-es module. Import each function you are using separately with import <function> from 'lodash-es/<function>'",
    },
    {
      name: 'clsx',
      importNames: ['default'],
      message: 'Use the named import instead: `import {clsx} from "clsx"`',
    },
    {
      name: '@github-ui/screen-size',
      message:
        'Avoid importing from screen-size. Instead, use CSS for resizing or consider a Primer component like https://primer-docs-preview.github.com/product/components/action-bar',
    },
    {
      name: '@github-ui/browser-history-state',
      message: 'This package is deprecated. Use `@github-ui/history` instead.',
    },
    {
      name: '@github-ui/ssr-utils',
      importNames: ['ssrSafeHistory'],
      message: "Please use `@github-ui/history` to access the browser's history.",
    },
  ],
  patterns: [
    {
      group: ['**/behaviors/**', '**/github/**', '**/marketing/**'],
      message:
        'Please do not import legacy modules into React code as they are not guaranteed to work in SSR. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/ssr/ssr-tools/#how-to-fix-no-restricted-imports-errors',
    },
    {
      group: ['*.server'],
      message:
        'Please do not import server modules directly. These will be swapped in during compilation of the alloy bundle. See https://thehub.github.com/epd/engineering/dev-practicals/frontend/react/ssr/ssr-tools/#server-aliases',
    },
    {
      group: [
        '**/hyperlist-web/**',
        '**/inbox/**',
        '**/blackbird-monolith/**',
        '**/repositories/**',
        '**/react-code-view/**',
        '**/repo-creation/**',
        '**/secret-scanning/**',
        '**/settings/notifications/**',
        '**/settings/rules/**',
        '**/virtual-network-settings/**',
      ],
      message: 'Please do not import react apps modules in react-shared',
    },
    {
      group: ['**/ui/packages/**'],
      message:
        'Please do not import packages directly. Instead install the package in your workspace as a dependency and import from `@github/<package-name>`',
    },
    {
      group: ['@github-ui/render-phase-provider'],
      importNames: ['useRenderPhase'],
      message:
        "Please use `useClientValue` instead. You can think of `useRenderPhase` as 'environment sniffing' vs `useClientValue`'s 'feature detection' approach.",
    },
    {
      group: ['highlight.js'],
      message: 'Use `@github-ui/highlight` instead.',
    },
    {
      group: ['@github/remote-form'],
      message: 'Use `@github-ui/remote-form` instead.',
    },
    {
      group: ['@github-ui/mock-fetch'],
      message:
        "Do not import the deprecated dependency 'mock-fetch'. Use 'import {worker} from '@github-ui/tests/browser'' instead. See docs: https://mswjs.io/docs/getting-started.",
    },
  ],
}

export function noRestrictedImportsRule({paths: additionalPaths = [], patterns: additionalPatterns = []} = {}) {
  return {
    'no-restricted-imports': [
      'error',
      {
        paths: [...noRestrictedImportsDefaults.paths, ...additionalPaths],
        patterns: [...noRestrictedImportsDefaults.patterns, ...additionalPatterns],
      },
    ],
  }
}
