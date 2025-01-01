// @ts-check

/**
 * Creates a loader with configuration for handling .yml and .yaml loading and transformation into JSON.
 *
 * @type {() => import('webpack').RuleSetRule}
 */
function createYamlLoaderRule() {
  return {
    test: /\.(yml|yaml)$/,
    type: 'json',
    parser: {
      parse: require('js-yaml').load,
    },
  }
}

module.exports = {createYamlLoaderRule}
