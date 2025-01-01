import securityCenterConfig from '@github-ui/security-center/eslint'

export default [
  ...securityCenterConfig,
  {
    rules: {
      '@github-ui/github-monorepo/no-sx': 'off',
    },
  },
]
