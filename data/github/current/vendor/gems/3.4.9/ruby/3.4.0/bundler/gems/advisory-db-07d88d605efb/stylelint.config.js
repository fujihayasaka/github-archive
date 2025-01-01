module.exports = {
  extends: ["@primer/stylelint-config"],
  customSyntax: "postcss-styled-syntax",
  rules: {
    "primer/borders": true,
    "primer/box-shadow": true,
    "primer/colors": true,
    "primer/spacing": true,
    "primer/typography": true,
    "primer/no-scale-colors": true,
    "primer/no-undefined-vars": [
      true,
      {
        files: [
          "**/*.scss",
          "!node_modules",
          "node_modules/@primer/css/**/*.scss",
          "node_modules/@primer/css-next/**/*.scss",
          "node_modules/@primer/primitives/dist/scss/**/*.scss",
        ],
        verbose: false,
      },
    ],
    "primer/no-override": [
      true,
      {
        // separating these out gives us better error messages
        bundles: ["utilities", "core", "product", "marketing"],
        ignoreSelectors: [
          // Primer CSS shouldn't be targeting these in the first place
          /^\.octicon[-a-z]*/,
          // same for .is-*...
          ".is-active",
          ".is-dragging",
          ".is-error",
          ".is-failed",
          ".is-failure",
          ".is-queued",
          ".is-pending",
          ".is-uploading",
          // used for responsive overrides
          ".page-responsive",
        ],
      },
    ],
    "selector-max-type": 1,
    "selector-no-qualifying-type": [
      true,
      {
        ignore: ["attribute"],
      },
    ],
    "plugin/no-unsupported-browser-features": [true, {
      "ignore": ["css-nesting"],
    }],
  },
};
