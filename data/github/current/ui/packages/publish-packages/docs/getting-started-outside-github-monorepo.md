# Getting Started outside of Dotcom

## Install package

1. Using a shared NPM token from 1Password
2. Add NPM token to your local `.npmrc`
3. Run `npm install <package name>`. Viola!

## Troubleshoot

### Styles

Most shared components use Primer and assume Primer base styling is already available. If you would like the same styling, please follow the steps below:

- Wrap `@primer/react` css in layer: [ui/packages/client-build-plugins/primer-react-css-layer.js](https://github.com/github/github/blob/master/ui/packages/client-build-plugins/primer-react-css-layer.js#L27). Here are examples of how to include it as a [Vite plugin](https://github.com/github/github/blob/master/ui/packages/vite/plugins/dotcom-css-plugin.ts#L4) or [Webpack plugin](https://github.com/github/github/blob/master/ui/packages/webpack/loaders/create-primer-react-loader-rule.js#L38 ) 
- Define the layer order in a CSS file similar to [layers.css](https://github.com/github/github/blob/master/app/assets/stylesheets/bundles/primer-primitives/layers.css)
- Install [Primer Primitive](https://primer.style/foundations/primitives/getting-started)
- Install [Primer CSS](https://primer.style/css/storybook/?path=/docs/gettingstarted--docs)

### Client-env

```
Uncaught Error: Client env was requested before it was loaded. This likely means you are attempting to use client env at the module level in SSR, which is not supported. Please move your client env usage into a function.
```

If this error displays in the console, the page is likely missing the client-env script. Add the following

```
    <script type="application/json" id="client-env">{ "featureFlags": [] }</script>
```
