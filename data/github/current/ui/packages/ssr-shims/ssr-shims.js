/* eslint no-undef: off */

const vfile = require.resolve('vfile').split('/').slice(0, -1).join('/')

// eslint-disable-next-line import/no-commonjs
module.exports = {
  ssrShimFileMap: {
    'delegated-events': require.resolve('./shims/delegated-events.ts'),
    dompurify: require.resolve('./shims/dompurify.ts'),
    '@github-ui/highlight': require.resolve('./shims/highlight.ts'),
    lowlight: require.resolve('./shims/lowlight.ts'),
    '@azure/search-documents': require.resolve('./shims/azure-search-documents.ts'),
    '@github/selector-observer': require.resolve('./shims/selector-observer.ts'),
    '@github/g-emoji-element': require.resolve('./shims/g-emoji-element.ts'),
    '@github/browser-support': require.resolve('./shims/browser-support.ts'),
    '@github/catalyst': require.resolve('./shims/catalyst.ts'),
    '@github-ui/jtml-shimmed': require.resolve('./shims/jtml.ts'),
    '@github-ui/microsoft-analytics/events': require.resolve('./shims/microsoft-analytics-events.ts'),
    '@github-ui/microsoft-analytics': require.resolve('./shims/microsoft-analytics.ts'),
    '@oddbird/popover-polyfill/fn': require.resolve('./shims/popover-polyfill-fn.ts'),
    '@oddbird/popover-polyfill': require.resolve('./shims/popover-polyfill.ts'),
    // The default versions of these use node dependencies when run in node. The so-called 'browser' versions don't
    // actually depend on any browser APIs so we can use those instead.
    '#minproc': require.resolve(`${vfile}/lib/minproc.browser.js`),
    '#minpath': require.resolve(`${vfile}/lib/minpath.browser.js`),
    '#minurl': require.resolve(`${vfile}/lib/minurl.browser.js`),
  },
}
