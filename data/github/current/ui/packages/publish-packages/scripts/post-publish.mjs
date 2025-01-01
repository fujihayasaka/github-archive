import {rmSync, readFileSync, writeFileSync} from 'node:fs'
import path from 'node:path'

// Access the argument passed from Bash
const [, , packagePath] = process.argv

const packageJsonPath = path.join(packagePath, './package.temp.json')
const packageJsonText = readFileSync(packageJsonPath, 'utf8')
const packageJson = JSON.parse(packageJsonText)

// Cleanup publish-specific fields
delete packageJson.types

writeFileSync(path.join(packagePath, './package.json'), `${JSON.stringify(packageJson, null, 2)}\n`, 'utf8')

// Delete the dist folder and temp package.json
rmSync('package.temp.json', {recursive: true}, () => {})
rmSync('dist', {recursive: true}, () => {})
