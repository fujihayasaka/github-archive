// prettier-ignore
// this is ordered by language so please don't prettier it
// via https://github.com/github/github/blob/be3faf1cb886269bf4f97ef288c01d3387022747/packages/copilot4prs/app/models/pull_requests/copilot/code_review_access.rb#L104
const SUPPORTED_FILE_EXTENSIONS = new Set([
  '.go',
  '.java', '.jav', '.jsh',
  '.md', '.livemd', '.markdown', '.mdown', '.mdwn', '.mkd', '.mkdn', '.mkdown', '.ronn', '.scd', '.workbook',
  '.rs', '.rs.in',
  '.ts', '.cts', '.mts',
  '.rb', '.builder', '.eye', '.fcgi', '.gemspec', '.god', '.jbuilder', '.mspec', '.pluginspec', '.podspec', '.prawn', '.rabl', '.rake', '.rbi', '.rbuild', '.rbw', '.rbx', '.ru', '.ruby', '.spec', '.thor', '.watchr',
  '.erb', '.erb.deface', '.rhtml',
  '.py', '.cgi', '.fcgi', '.gyp', '.gypi', '.lmi', '.py3', '.pyde', '.pyi', '.pyp', '.pyt', '.pyw', '.rpy', '.spec', '.tac', '.wsgi', '.xpy',
  '.toml',
  '.yml', '.mir', '.reek', '.rviz', '.sublime-syntax', '.syntax', '.yaml', '.yaml-tmlanguage', '.yaml.sed', '.yml.mysql',
  '.proto',
  '.tsx',
  '.js', '._js', '.bones', '.cjs', '.es', '.es6', '.frag', '.gs', '.jake', '.javascript', '.jsb', '.jscad', '.jsfl', '.jslib', '.jsm', '.jspre', '.jss', '.jsx', '.mjs', '.njs', '.pac', '.sjs', '.ssjs', '.xsjs', '.xsjslib',
  '.vue',
  '.csl', '.kql',
  '.rs', '.rsh',
  '.md',
  '.cs', '.cake', '.cs.pp', '.csx', '.linq',
  '.cshtml', '.razor',
  '.jsp', '.tag',
  '.ipynb',
  '.js.erb',
])

export const checkIsFilePathSupportedLanguage = (filePath: string) => {
  const combinedExtensionParts = new Set()

  // allow extension-less file paths like *
  const extensionIndex = filePath.indexOf('.')
  if (extensionIndex === -1) {
    return true
  }

  // for the example path **/*.test.tsx this would add .test.tsx
  const fullExtension = filePath.substring(extensionIndex)
  combinedExtensionParts.add(fullExtension)

  // for the example path **/*.test.tsx this would add .tsx
  const extensionParts = fullExtension.split('.').filter(part => !!part)
  if (extensionParts.length > 1) {
    combinedExtensionParts.add(`.${extensionParts[extensionParts.length - 1]}`)
  }

  return !isDisjointFrom(combinedExtensionParts, SUPPORTED_FILE_EXTENSIONS)
}

function isDisjointFrom(set: Set<unknown>, otherSet: Set<unknown>) {
  for (const item of otherSet) {
    if (set.has(item)) {
      return false // Found a common element
    }
  }
  return true // No common elements
}
