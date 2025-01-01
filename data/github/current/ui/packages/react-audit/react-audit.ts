import {spawnSync} from 'node:child_process'
import {type PropertyAssignment, type ObjectLiteralExpression, type CallExpression, Project, SyntaxKind} from 'ts-morph'

function stripQuotesFromStringLiteral(s: string): string {
  return s.slice(1, s.length - 1)
}

export function getGithubReactRoutes() {
  // first find the files using some CLI tools instead of ts-morph (for performance?):
  const find = spawnSync('find', ['../../../app/assets', '../..', '-iname', '*.ts', '-o', '-iname', '*.tsx'])
  const allTsFiles = find.stdout.toString('utf8').trim().split('\n')
  const grep = spawnSync('grep', ['-He', 'registerNavigatorApp', ...allTsFiles])
  const grepResults = grep.stdout.toString('utf8').trim().split('\n')
  const filenamesWithRepeats = grepResults.map(line => line.split(':')[0]!)
  const filenames: string[] = Array.from(new Set(filenamesWithRepeats))
  // console.info(`🏭 Found ${filenames.length} files containing "registerNavigatorApp"`)

  const project = new Project({
    tsConfigFilePath: './tsconfig.json',
    skipAddingFilesFromTsConfig: true,
  })
  project.addSourceFilesAtPaths(filenames)

  const routes = []

  for (const file of project.getSourceFiles()) {
    // find invocations of `registerNavigatorApp`:
    const registerCallExpressions: CallExpression[] = file
      .getDescendantsOfKind(SyntaxKind.CallExpression)
      .filter(call => {
        call.getArguments()
        return call.getExpression().getText() === 'registerNavigatorApp'
      })

    for (const registerCall of registerCallExpressions) {
      const quotedAppName = registerCall.getArguments()[0]!.getText()
      const appName = stripQuotesFromStringLiteral(quotedAppName)
      // console.log(`📦 Found app ${appName} in ${file.getFilePath()}`)

      const relayRoutes = file.getDescendantsOfKind(SyntaxKind.CallExpression).filter(call => {
        return call.getExpression().getText() === 'relayRoute'
      })
      for (const relayRoute of relayRoutes) {
        const routeArgsObjectLiteral = relayRoute.getArguments()[0] as ObjectLiteralExpression
        const path = stripQuotesFromStringLiteral(
          (routeArgsObjectLiteral.getPropertyOrThrow('path') as PropertyAssignment).getInitializer()!.getText(),
        )

        routes.push({path, appName, ['route type']: 'relayRoute', file: file.getFilePath()})
      }

      const jsonRoutes = file.getDescendantsOfKind(SyntaxKind.CallExpression).filter(call => {
        return call.getExpression().getText() === 'jsonRoute'
      })
      for (const jsonRoute of jsonRoutes) {
        try {
          const routeArgsObjectLiteral = jsonRoute.getArguments()[0] as ObjectLiteralExpression
          const path = stripQuotesFromStringLiteral(
            (routeArgsObjectLiteral.getPropertyOrThrow('path') as PropertyAssignment).getInitializer()!.getText(),
          )

          routes.push({path, appName, ['route type']: 'jsonRoute', file: file.getFilePath()})
        } catch {
          console.log('Trouble with this route:', jsonRoute.getText())
        }
      }
    }
  }
  return routes
}

console.table(getGithubReactRoutes())
console.log('⚠️ note that this list does not include memex.')
