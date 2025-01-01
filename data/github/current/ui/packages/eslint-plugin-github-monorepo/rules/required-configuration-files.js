const {existsSync, writeFileSync, readFileSync, unlinkSync} = require('fs')
const {join, dirname} = require('path')
const REQUIRED_FILES = ['tsconfig.json', 'jest.config.js']

module.exports = {
  meta: {
    type: 'problem',
    docs: {
      description: `Monorepo packages require (${REQUIRED_FILES.join(
        ', ',
      )}) files in the root. If "@github-ui/tests" is a devDependency, jest.config.js is not required unless "scripts.test" is set to "jest".`,
    },
    schema: [],
    messages: {
      missingFile: 'Missing required file "{{file}}" in the package root',
      unnecessaryFile:
        'Unnecessary file "{{file}}" found in the package root when "@github-ui/tests" is a devDependency and "scripts.test" is not set to "jest"',
    },
  },

  create(context) {
    return {
      'Program:exit': node => {
        const path = dirname(context.getPhysicalFilename())
        const packageJsonPath = join(path, 'package.json')

        let isUsingGithubUITests = false
        let isTestScriptJest = false

        const checkAndFixRequiredFile = (filepath, file) => {
          if (!existsSync(join(filepath, file))) {
            context.report({
              node,
              messageId: 'missingFile',
              data: {file},
              fix: () => {
                try {
                  const content = readFileSync(
                    join(__dirname, '../../ui-packages-tooling/templates', `${file}.hbs`),
                    'utf8',
                  )
                  writeFileSync(join(filepath, file), content)
                } catch (error) {
                  console.error(`Failed to write ${file}: ${error.message}`)
                }
              },
            })
          }
        }

        if (existsSync(packageJsonPath)) {
          try {
            const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'))
            isUsingGithubUITests = packageJson.devDependencies && packageJson.devDependencies['@github-ui/tests']
            isTestScriptJest = packageJson.scripts && packageJson.scripts.test === 'jest'
          } catch (error) {
            context.report({
              node,
              message: `Error reading package.json: ${error.message}`,
            })
            return
          }
        }

        if (!isUsingGithubUITests) {
          // If not using @github-ui/tests, check for all required files
          for (const file of REQUIRED_FILES) {
            checkAndFixRequiredFile(path, file)
          }
        } else {
          if (isTestScriptJest) {
            // If using @github-ui/tests and test script is "jest", check for all required files
            for (const file of REQUIRED_FILES) {
              checkAndFixRequiredFile(path, file)
            }
          } else {
            // If using @github-ui/tests but test script is not "jest"
            const jestConfigPath = join(path, 'jest.config.js')
            if (existsSync(jestConfigPath)) {
              context.report({
                node,
                messageId: 'unnecessaryFile',
                data: {file: 'jest.config.js'},
                fix: () => {
                  try {
                    unlinkSync(jestConfigPath)
                  } catch (error) {
                    console.error(`Failed to delete jest.config.js: ${error.message}`)
                  }
                },
              })
            }

            const tsconfigPath = join(path, 'tsconfig.json')
            if (!existsSync(tsconfigPath)) {
              context.report({
                node,
                messageId: 'missingFile',
                data: {file: 'tsconfig.json'},
                fix: () => {
                  try {
                    const content = readFileSync(
                      join(__dirname, '../../ui-packages-tooling/templates', 'tsconfig.json.hbs'),
                      'utf8',
                    )
                    writeFileSync(tsconfigPath, content)
                  } catch (error) {
                    console.error(`Failed to write tsconfig.json: ${error.message}`)
                  }
                },
              })
            }
          }
        }
      },
    }
  },
}
