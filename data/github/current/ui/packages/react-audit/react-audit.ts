import {globFromRoot} from '@github-ui/client-build-tools/path-utils'
import {spawnSync} from 'node:child_process'
import type {
  StringLiteral,
  PropertyAssignment,
  ObjectLiteralExpression,
  CallExpression,
  Identifier,
  VariableDeclaration,
  PropertyAccessExpression,
  Expression,
} from 'ts-morph'
import {Project, SyntaxKind} from 'ts-morph'

function stripQuotesFromStringLiteral(s: string): string {
  return s.replaceAll(/'|"|`/g, '')
}

interface DataRouterRoute {
  appName?: string
  routes: Array<{
    path: string
    file: string
    routeId: string
  }>
}

function extractValueFromIdentifier(node: Identifier, propertyName: string = '') {
  const definition = node.getDefinitionNodes()[0]!
  const initializer = (definition as VariableDeclaration).getInitializer()!

  switch (initializer.getKind()) {
    case SyntaxKind.StringLiteral:
    case SyntaxKind.NoSubstitutionTemplateLiteral: {
      return stripQuotesFromStringLiteral(initializer.getText())
    }
    case SyntaxKind.ObjectLiteralExpression: {
      const property = (initializer as ObjectLiteralExpression).getPropertyOrThrow(propertyName) as PropertyAssignment
      return stripQuotesFromStringLiteral(property.getInitializer()!.getText())
    }
    case SyntaxKind.Identifier: {
      return extractValueFromIdentifier(initializer as Identifier)
    }
    default: {
      throw new Error('Initializer not supported')
    }
  }
}

function getPathFromArgs(initializer: Expression) {
  try {
    switch (initializer.getKind()) {
      case SyntaxKind.StringLiteral:
      case SyntaxKind.NoSubstitutionTemplateLiteral: {
        return stripQuotesFromStringLiteral(initializer.getText())
      }
      case SyntaxKind.Identifier: {
        return extractValueFromIdentifier(initializer as Identifier)
      }
      case SyntaxKind.PropertyAccessExpression: {
        const propertyAccess = initializer as PropertyAccessExpression
        return extractValueFromIdentifier(propertyAccess.getExpression() as Identifier, propertyAccess.getName())
      }
      default: {
        throw new Error('Initializer not supported')
      }
    }
  } catch {
    return stripQuotesFromStringLiteral(initializer.getText())
  }
}

function findTsFiles() {
  const allTsFiles = [...globFromRoot('app/assets/**/*.{ts,tsx}'), ...globFromRoot('ui/packages/**/*.{ts,tsx}')].filter(
    file => !file.match(/\.test\./),
  )
  const grep = spawnSync('grep', [
    '-H',
    '-e',
    'registerNavigatorApp',
    '-e',
    'DataRouterApplicationBuilder.create',
    '-e',
    'createQueryRouteConfig',
    ...allTsFiles,
  ])
  const grepResults = grep.stdout.toString('utf8').trim().split('\n')
  const filenamesWithRepeats = grepResults.map(line => line.split(':')[0]!)
  return Array.from(new Set(filenamesWithRepeats))
}

export function getGithubReactRoutes(filename?: string) {
  let filenames: string[] = []
  if (filename) {
    filenames = [filename]
  } else {
    filenames = findTsFiles()
  }

  const dataRouterRoutes: {[builderName: string]: DataRouterRoute} = {}

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
        const initializer = (routeArgsObjectLiteral.getPropertyOrThrow('path') as PropertyAssignment).getInitializer()!
        const path = getPathFromArgs(initializer)

        routes.push({path, appName, ['route type']: 'relayRoute', file: file.getFilePath()})
      }

      const jsonRoutes = file.getDescendantsOfKind(SyntaxKind.CallExpression).filter(call => {
        return call.getExpression().getText() === 'jsonRoute'
      })
      for (const jsonRoute of jsonRoutes) {
        try {
          const routeArgsObjectLiteral = jsonRoute.getArguments()[0] as ObjectLiteralExpression
          const initializer = (
            routeArgsObjectLiteral.getPropertyOrThrow('path') as PropertyAssignment
          ).getInitializer()!
          const path = getPathFromArgs(initializer)

          routes.push({path, appName, ['route type']: 'jsonRoute', file: file.getFilePath()})
        } catch {
          console.log('Trouble with this route:', jsonRoute.getText())
        }
      }
    }

    // find invocations of `DataRouterApplicationBuilder.create`:
    const dataRouterBuilderExpressions: CallExpression[] = file
      .getDescendantsOfKind(SyntaxKind.CallExpression)
      .filter(call => {
        return call.getExpression().getText() === 'DataRouterApplicationBuilder.create'
      })

    for (const dataRouterBuilder of dataRouterBuilderExpressions) {
      const builderName = dataRouterBuilder.getParentIfKindOrThrow(SyntaxKind.VariableDeclaration)?.getName()
      const appNameLiteral = dataRouterBuilder.getArguments()[0] as StringLiteral
      const appName = stripQuotesFromStringLiteral(appNameLiteral.getText())

      // app and route registration happen in separate files, so a route may have already been registered to this
      // builder name
      if (dataRouterRoutes[builderName]) {
        dataRouterRoutes[builderName].appName = appName
      } else {
        dataRouterRoutes[builderName] = {
          appName,
          routes: [],
        }
      }
    }

    // find invocations of `DataRouterApplicationBuilder.create`:
    const createQueryRouteConfigCallExpressions: CallExpression[] = file
      .getDescendantsOfKind(SyntaxKind.CallExpression)
      .filter(call => {
        return call.getExpressionIfKind(SyntaxKind.PropertyAccessExpression)?.getName() === 'createQueryRouteConfig'
      })

    for (const createQueryRouteConfigCall of createQueryRouteConfigCallExpressions) {
      const builderName = createQueryRouteConfigCall
        .getExpressionIfKindOrThrow(SyntaxKind.PropertyAccessExpression)
        .getExpression()
        .getText()
      const routeId = stripQuotesFromStringLiteral(
        (createQueryRouteConfigCall.getArguments()[0] as StringLiteral).getText(),
      )

      const pathArgument = createQueryRouteConfigCall.getArguments()[1] as ObjectLiteralExpression
      const initializer = (pathArgument.getPropertyOrThrow('path') as PropertyAssignment).getInitializer()!
      const path = getPathFromArgs(initializer)

      const routeInfo = {
        path,
        file: file.getFilePath(),
        routeId,
      }
      // app and route registration happen in separate files, so a route may have already been registered to this
      // builder name
      if (dataRouterRoutes[builderName]) {
        dataRouterRoutes[builderName].routes.push(routeInfo)
      } else {
        dataRouterRoutes[builderName] = {
          routes: [routeInfo],
        }
      }
    }
  }

  for (const routeInfo of Object.values(dataRouterRoutes)) {
    for (const {path, file, routeId} of routeInfo.routes) {
      routes.push({path, appName: routeInfo.appName, ['route type']: 'dataRoute', file, routeId})
    }
  }

  return routes
}

console.table(getGithubReactRoutes(process.argv[2]))
console.log('⚠️ note that this list does not include memex.')
