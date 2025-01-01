# Getting Started in Dotcom

## Initial Setup

In a codespace, run `scaffold-ui-package` and select "Upgrade a ui/package to be publishable" and run through the necessary steps

- If you do not have a package, create one using the options in `scaffold-ui-package`

## Build and Publish

1. Open a codespace and run `npm adduser` in the console and login to your NPM account.
2. In the console, change directory into your package: `cd ui/packages/<folder>`
3. Run `npm run build:publish` inside the package directory in the console. This will generate a `dist/` folder with compiled `.js`, `.css`, and `.d.ts`. Continue to follow the console until the package is published.
4. Confirm your package is available at `https://www.npmjs.com/package/<package name>`. It may take a minute to see package in the @github-ui namespace

## Reminders

- The `version` defined in the package.json is the version the package will be published at. If publishing a new package, be sure to update the `version` and `npm i` to update the package-lock.json

## Unpublish

If you wish to unpublish your package, be aware of [NPM Unpublish Policy](https://docs.npmjs.com/policies/unpublish) as it becomes more strict and difficult to unpublish past 72 hours

Based on [NPM Unpublishing Documentation](https://docs.npmjs.com/unpublishing-packages-from-the-registry), you can unpublish by doing either of the following:

- Using UI <br />
  <img src="https://github.com/user-attachments/assets/0c0e77ab-cdb4-4fe4-a4c5-f21da45ae01d" alt="settings page on package" width="500"/>
- Using command line, run `npm unpublish <package-name>@<version>`

## Troubleshoot

- `npm run build` to rebuild the `/dist` folder
- `npm run build:types` to rebuild the `.d.ts` files
