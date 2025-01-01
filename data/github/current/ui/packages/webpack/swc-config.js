const swcConfig = require('@github-ui/swc/config')

const {NODE_ENV = 'development', WEBPACK_SERVE} = process.env

const supportReactRefresh = NODE_ENV === 'development' && WEBPACK_SERVE === 'true'

const alteredSwcConfig = supportReactRefresh
  ? swcConfig
  : {
      ...swcConfig,
      jsc: {
        ...swcConfig.jsc,
        transform: {
          ...swcConfig.jsc?.transform,
          react: {
            ...swcConfig.jsc?.transform?.react,
            refresh: false, // Disable React Refresh for non-hmr environments
          },
        },
      },
    }

module.exports = {
  swcConfig: alteredSwcConfig,
  supportReactRefresh,
}
