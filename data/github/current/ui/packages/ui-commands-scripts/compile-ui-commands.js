const {getRepoAgnosticPath, rootPath} = require('@github-ui/client-build-tools/path-utils')
const writeCommandFiles = require('./write-command-files')

writeCommandFiles(rootPath, console, {
  path: getRepoAgnosticPath('ui/packages/ui-commands/__generated__'),
  file: 'ui-commands',
  env: process.env.NODE_ENV,
})
