// @ts-check

import {mkdirSync, readFileSync, writeFileSync} from 'node:fs'
import path from 'node:path'
import {build} from 'esbuild'

// Access the argument passed from Bash
const [, , packagePath] = process.argv
const packageJsonText = readFileSync(path.join(packagePath || '.', './package.json'), 'utf8')
const packageJson = JSON.parse(packageJsonText)

/** @type {Array<string>} */
const externalDependencyExceptions = []

// Find external dependencies
const externalDependencies = new Set()
if (packageJson.dependencies) {
  const dependencies = packageJson.dependencies
  for (const dependency in dependencies) {
    if (!dependency.startsWith('@github-ui') && !externalDependencyExceptions.includes(dependency)) {
      externalDependencies.add(dependency)
    }
  }
}

// Find entrypoints from packageJson exports
const entryPoints = new Set()
if (packageJson.exports) {
  const xports = packageJson.exports
  for (const exportDir in xports) {
    entryPoints.add(xports[exportDir])
  }
}

build({
  entryPoints: [...entryPoints],
  outdir: 'dist',
  outbase: './',
  bundle: true,
  format: 'esm',
  // minify: true,
  platform: 'browser',
  define: {
    'process.env.APP_ENV': '"production"',
  },
  external: ['react', 'react-dom', ...externalDependencies],
  plugins: [
    {
      name: 'insert-css-into-output-files',
      setup(builder) {
        // Manually output esbuild files to access outputFiles
        const write = builder.initialOptions.write
        builder.initialOptions.write = false

        builder.onEnd(args => {
          /** @type {Array<{path: string, contents: Uint8Array}> | undefined} */
          const outputFiles = args.outputFiles
          if (outputFiles) {
            for (const file of outputFiles) {
              const {contents, path: filePath} = file
              const data = new TextDecoder().decode(contents)
              let combinedData = data

              if (path.extname(filePath) === '.js') {
                const matchingCssFile = outputFiles.find(f => {
                  const parsedFilePath = path.parse(filePath)
                  const parsedFPath = path.parse(f.path)

                  return (
                    parsedFPath.ext === '.css' &&
                    parsedFPath.dir === parsedFilePath.dir &&
                    parsedFPath.name === parsedFilePath.name
                  )
                })

                if (matchingCssFile) {
                  // Insert CSS file into JS file
                  combinedData = `import './${path.basename(matchingCssFile.path)}'\n${combinedData}`
                }
              }

              if (write === undefined || write) {
                mkdirSync(path.dirname(filePath), {recursive: true})
                writeFileSync(filePath, combinedData, 'utf8')
              }
            }
          }
        })
      },
    },
  ],
})
