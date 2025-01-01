/*
 * Generates a metadata.json for each package with a /primer-docs folder
 *
 * metadata.json gathers information about the package, props, and subcomponents
 * to be used in primer-docs
 */

import type {TypeChecker, SourceFile, Type, JSDoc, Symbol} from 'ts-morph'
import {Project, Node, ScriptTarget, ModuleKind} from 'ts-morph'
import path, {dirname} from 'node:path'
import {existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync} from 'node:fs'
// DOES NOT SUPPORT CLASS COMPONENTS

const BASE_DIR = path.join(process.cwd(), '../') // TODO: depending on where file lives, this may need to be adjusted

export interface PropMetadata {
  name: string
  type: string
  defaultValue: string
  required: boolean
  description: string
}

export interface ComponentMetadata {
  name: string
  props: PropMetadata[]
}

export interface SubcomponentMetadata extends ComponentMetadata {
  // Any additional subcomponent-specific fields
}

export interface MainComponentMetadata {
  source: string
  id: string
  name: string
  status: string
  a11yReviewed: boolean
  stories: Array<{id: string}>
  importPath: string
  props: PropMetadata[]
  subcomponents: SubcomponentMetadata[]
}

export interface MetadataOutput {
  [componentId: string]: MainComponentMetadata
}

/**
 * Extracts a clean type string from a TypeScript type
 */
function getTypeString(type: Type): string {
  const typeString = type.getText().replace(/import\([^)]+\)\./g, '')
  return typeString
}

/**
 * Parse JSDoc comment to extract description
 */
function extractJSDocDescription(jsDoc: JSDoc | undefined): string {
  if (!jsDoc) return ''
  const description = jsDoc.getDescription().trim()
  return description
}

/**
 * Extract default value from initializer or JSDoc @default tag
 */
function extractDefaultValue(symbol: Symbol, jsDoc: JSDoc | undefined): string {
  if (!symbol || !symbol.getValueDeclaration()) return ''

  const valueDeclaration = symbol.getValueDeclaration()
  let defaultValue = ''

  // Try to get default value from property initializer
  if (Node.isPropertySignature(valueDeclaration) && valueDeclaration.getInitializer()) {
    defaultValue = valueDeclaration.getInitializer()!.getText()
  }

  // Or try to get it from JSDoc @default tag
  if (jsDoc) {
    const defaultTag = jsDoc.getTags().find(tag => tag.getTagName() === 'default')
    if (defaultTag) {
      defaultValue = defaultTag.getCommentText() || ''
    }
  }

  return defaultValue
}

/**
 * Process a component interface to extract props, avoiding duplicates
 */
function processComponentProps(interfaceDeclaration: Node, typeChecker: TypeChecker): PropMetadata[] {
  // Use a Map to track properties by name and avoid duplicates
  const propMap = new Map<string, PropMetadata>()
  const type = typeChecker.getTypeAtLocation(interfaceDeclaration)

  // Filter out props not defined within the package
  const properties = type.getProperties().filter(property => {
    const declarations = property.getDeclarations()
    const declaration = declarations?.[0]
    if (declaration) {
      // If the property comes from node modules, then skip it
      const sourceFilePath = declaration?.getSourceFile().getFilePath()
      if (sourceFilePath && sourceFilePath.includes('node_modules')) {
        return false
      }
    }

    return true
  })

  for (const property of properties) {
    const propertyName = property.getName()

    // Skip if we've already processed this property
    if (propMap.has(propertyName)) {
      continue
    }

    const propertyDeclaration = property.getValueDeclaration()
    let jsDoc: JSDoc | undefined

    if (propertyDeclaration && Node.isJSDocable(propertyDeclaration)) {
      const jsDocs = propertyDeclaration.getJsDocs()
      if (jsDocs.length > 0) {
        jsDoc = jsDocs[0]
      }
    }

    const propertyType = propertyDeclaration && property.getTypeAtLocation(propertyDeclaration)
    const typeString = propertyType && getTypeString(propertyType)
    const isOptional =
      propertyDeclaration && Node.isPropertySignature(propertyDeclaration) && propertyDeclaration.hasQuestionToken()
    const description = (jsDoc && extractJSDocDescription(jsDoc)) || ''
    const defaultValue = extractDefaultValue(property, jsDoc)

    // Add to the map instead of the array
    propMap.set(propertyName, {
      name: propertyName,
      type: typeString || '',
      defaultValue,
      required: !isOptional,
      description: description || '',
    })
  }

  // Convert the map values to an array for return
  return Array.from(propMap.values())
}

/**
 * Find all prop types for each component in a source file
 * @returns Map of component names to their prop types
 */
function findComponentPropTypes(sourceFile: SourceFile, typeChecker: TypeChecker): Map<string, Node> {
  const componentPropMap = new Map<string, Node>()
  const explicitPropTypes = new Map<string, Node>()

  // Find interfaces that follow prop naming conventions
  const interfaces = sourceFile.getInterfaces()
  for (const iface of interfaces) {
    const name = iface.getName()
    if (name.endsWith('Props') || name.endsWith('Properties')) {
      explicitPropTypes.set(name, iface)
    }
  }

  // Find type aliases that follow prop naming conventions
  const typeAliases = sourceFile.getTypeAliases()
  for (const typeAlias of typeAliases) {
    const name = typeAlias.getName()
    if (name.endsWith('Props') || name.endsWith('Properties')) {
      explicitPropTypes.set(name, typeAlias)
    }
  }

  // Find function components with inline prop definitions
  const functions = sourceFile.getFunctions()
  for (const func of functions) {
    const returnType = func.getReturnType().getText()
    // Check if this is a React component
    if (
      returnType.includes('JSX.Element') ||
      returnType.includes('React.ReactNode') ||
      returnType.includes('ReactElement')
    ) {
      const componentName = func.getName() || 'UnnamedComponent'
      const params = func.getParameters()
      if (params.length > 0) {
        const propsParam = params[0]

        // Case: Inline prop type - function Component({prop1, prop2}: {prop1: type, prop2: type})
        const paramType = propsParam?.getTypeNode()
        if (paramType && Node.isTypeLiteral(paramType)) {
          componentPropMap.set(componentName, paramType)
        }
        // Case: Handle intersection types (like Props & {html: string})
        else if (paramType && Node.isIntersectionTypeNode(paramType)) {
          // Get the first type in the intersection which is likely the named type
          const types = paramType.getTypeNodes()
          if (types.length > 0) {
            const firstTypeName = types[0]?.getText().trim()
            // Look for matching explicit prop type
            for (const [name, node] of explicitPropTypes.entries()) {
              if (firstTypeName === name) {
                componentPropMap.set(componentName, node)
                break
              }
            }

            // If not found by name, use the intersection type node itself
            if (!componentPropMap.has(componentName)) {
              componentPropMap.set(componentName, paramType)
            }
          }
        }
        // Case: Named prop type - function Component(props: ComponentProps)
        else {
          try {
            const type = propsParam?.getType()
            if (type?.getSymbol()) {
              const declarations = type.getSymbol()?.getDeclarations()
              if (declarations?.[0]) {
                componentPropMap.set(componentName, declarations[0])

                // Look for props that match naming conventions (e.g., "ListItemProps" for "ListItem")
                const expectedPropName = `${componentName}Props`
                if (explicitPropTypes.has(expectedPropName)) {
                  componentPropMap.set(componentName, explicitPropTypes.get(expectedPropName)!)
                }
              }
            }
          } catch (e) {
            console.warn(`Error getting type for ${componentName} parameters`, e)
          }
        }
      } else {
        // Component takes no props, but we should still record it
        // Look for matching prop types by name convention
        const expectedPropName = `${componentName}Props`
        if (explicitPropTypes.has(expectedPropName)) {
          componentPropMap.set(componentName, explicitPropTypes.get(expectedPropName)!)
        }
      }
    }
  }

  // Find arrow function components and match with prop types
  for (const node of sourceFile.getDescendants()) {
    if (Node.isVariableDeclaration(node)) {
      const initializer = node.getInitializer()
      const componentName = node.getName()

      if (Node.isArrowFunction(initializer) || Node.isFunctionExpression(initializer)) {
        try {
          // Check if this is a React component by examining return type
          const signature = typeChecker.getSignatureFromNode(initializer)
          const returnType = signature && typeChecker.getReturnTypeOfSignature(signature)
          const returnTypeText = returnType?.getText()

          const isComponent =
            !!returnTypeText &&
            (returnTypeText.includes('JSX.Element') ||
              returnTypeText.includes('React.ReactNode') ||
              returnTypeText.includes('ReactElement'))

          if (isComponent) {
            const params = initializer.getParameters()

            if (params.length > 0) {
              const propsParam = params[0]

              // Case: Inline prop type
              const paramType = propsParam?.getTypeNode()
              if (paramType && Node.isTypeLiteral(paramType)) {
                componentPropMap.set(componentName, paramType)
              }
              // Case: Named prop type reference
              else {
                try {
                  const type = propsParam?.getType()
                  if (type?.getSymbol()) {
                    const declarations = type.getSymbol()?.getDeclarations()
                    if (declarations?.[0]) {
                      componentPropMap.set(componentName, declarations[0])
                    }
                  }
                } catch (e) {
                  console.warn(`Error getting type for ${componentName} arrow function parameters`, e)
                }
              }
            } else {
              // Component takes no props, but we should still check for matching prop types
              const expectedPropName = `${componentName}Props`
              if (explicitPropTypes.has(expectedPropName)) {
                componentPropMap.set(componentName, explicitPropTypes.get(expectedPropName)!)
              }
            }
          }
        } catch {
          // Ignore errors determining if this is a component
        }
      }
    }
  }

  // Look for exports that might match components
  const exportedDeclarations = sourceFile.getExportedDeclarations()
  for (const [exportName, declarations] of exportedDeclarations) {
    // If this is a type export with Props in the name, try to match it to a component
    if (exportName.endsWith('Props') || exportName.endsWith('Properties')) {
      const componentName = exportName.replace(/Props$|Properties$/, '')

      // Only add if the component exists and doesn't already have props assigned
      if (!componentPropMap.has(componentName) && declarations?.[0]) {
        componentPropMap.set(componentName, declarations[0])
      }
    }
  }

  return componentPropMap
}

/*
 * Find all exported paths in package.json
 */
function findExportedPaths(packageJsonExports: string | string[] | {}) {
  // Extract file paths from package.json exports
  const exportPaths: string[] = []
  if (packageJsonExports) {
    // Handle both string and object exports
    if (typeof packageJsonExports === 'string') {
      exportPaths.push(packageJsonExports)
    } else {
      // Handle object exports
      for (const exportPath of Object.values(packageJsonExports)) {
        if (typeof exportPath === 'string') {
          exportPaths.push(exportPath)
        } else if (exportPath && typeof exportPath === 'object') {
          // Handle conditional exports
          for (const conditionalPath of Object.values(exportPath)) {
            if (typeof conditionalPath === 'string') {
              exportPaths.push(conditionalPath)
            }
          }
        }
      }
    }
  }

  return exportPaths
}

/**
 * Main function to generate metadata
 * * @param packageFolderName - The folder name of the component
 */
async function generateMetadata(packageFolderName: string): Promise<void> {
  const outputPath = path.resolve(BASE_DIR, packageFolderName, 'primer-docs/metadata.json')
  const metadata: MetadataOutput = {}

  // 1. Get component metadata from the package.json file
  const packageJsonText = readFileSync(path.join(BASE_DIR, packageFolderName, './package.json'), 'utf8')
  const packageJson = JSON.parse(packageJsonText)
  const {
    name: packageName,
    componentInfo: {name, status: storybookStatus, a11yReviewed},
    main: mainExportedPath,
  } = packageJson
  const exportPaths = findExportedPaths(packageJson.exports)
  const absoluteExportPaths = exportPaths.map(exportPath => path.resolve(BASE_DIR, packageFolderName, exportPath))

  // 2. Create "props" and "subcomponents" arrays
  const project = new Project({
    compilerOptions: {
      target: ScriptTarget.ESNext,
      module: ModuleKind.ESNext,
      esModuleInterop: true,
    },
  })
  project.addSourceFilesAtPaths(absoluteExportPaths)
  let props: PropMetadata[] = []
  const subcomponents: SubcomponentMetadata[] = []

  for (const sourceFile of project.getSourceFiles()) {
    console.log(`Processing file: ${sourceFile.getFilePath()}`)

    // Get all component prop types in this file
    const componentPropTypes = findComponentPropTypes(sourceFile, project.getTypeChecker())

    // Uses the "main" export to determine the props of the main component
    if (sourceFile.getFilePath() === path.resolve(BASE_DIR, packageFolderName, mainExportedPath)) {
      // For main component file, extract the main component's props
      const mainComponentName = path.basename(mainExportedPath, path.extname(mainExportedPath))
      const propNode = componentPropTypes.get(mainComponentName)
      if (propNode) {
        props = processComponentProps(propNode, project.getTypeChecker())
      } else {
        console.warn(`No prop type found for the main component: ${mainComponentName}`)
      }

      // All other components in the main file are subcomponents
      for (const [componentName, node] of componentPropTypes) {
        const isExported = sourceFile.getExportedDeclarations().has(componentName)
        if (componentName !== mainComponentName && isExported) {
          const subcomponentProps = processComponentProps(node, project.getTypeChecker())
          subcomponents.push({
            name: componentName,
            props: subcomponentProps,
          })
        }
      }

      continue
    }

    // For other files, all exported components are subcomponents
    for (const [componentName, node] of componentPropTypes) {
      const isExported = sourceFile.getExportedDeclarations().has(componentName)
      if (isExported) {
        const subcomponentProps = processComponentProps(node, project.getTypeChecker())
        if (subcomponentProps.length > 0) {
          subcomponents.push({
            name: componentName,
            props: subcomponentProps,
          })
        }
      }
    }
  }

  // 3.Create component ID to match primer-docs format
  // Convert to snakecase. Ex: list-view -> list_view
  const componentId = packageFolderName.replace(/-/g, '_')

  // 4. Combine all the data into metadata object
  // type Status = 'ready' | 'draft' | 'deprecated' | 'a11yReviewed' | 'a11yNotReviewed'
  // https://github.com/github/primer-docs/blob/main/src/components/content/status-label/StatusLabel.tsx#L4
  const status = storybookStatus === 'Ready' ? 'ready' : 'draft'
  metadata[componentId] = {
    source: `https://github.com/github/github/tree/master/ui/packages/${packageFolderName}`,
    id: componentId,
    name,
    status,
    a11yReviewed: a11yReviewed || false,
    stories: [{id: `components-${componentId.toLowerCase()}--default`}], // TODO: Components need a default story?
    importPath: packageName,
    props,
    subcomponents,
  }

  // 5. Write metadata to file
  // Ensure the directory exists
  const outputDir = dirname(outputPath)
  if (!existsSync(outputDir)) {
    mkdirSync(outputDir, {recursive: true})
  }
  writeFileSync(outputPath, JSON.stringify(metadata, null, 2), 'utf8')
  console.log(`Metadata generated at ${outputPath}`)
}

/*
 * Find all packages with a primer-docs folder
 */
function findPackagesWithPrimerDocs(): string[] {
  const packagesDir = path.resolve(process.cwd(), '../')
  const packages: string[] = []

  try {
    const entries = readdirSync(packagesDir, {withFileTypes: true})

    for (const entry of entries) {
      if (entry.isDirectory()) {
        const packagePath = path.join(packagesDir, entry.name)
        const primerDocsPath = path.join(packagePath, 'primer-docs')

        if (existsSync(primerDocsPath)) {
          packages.push(entry.name)
        }
      }
    }
  } catch (error) {
    console.error('Error finding packages:', error)
  }

  return packages
}

async function main() {
  const packages = findPackagesWithPrimerDocs()
  console.log('Packages with primer-docs folders:', packages)
  console.log('-----------')

  // Generate metadata for each package
  for (const packageName of packages) {
    await generateMetadata(packageName)
    console.log('-----------')
  }
}

main()
