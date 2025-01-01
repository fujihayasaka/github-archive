import {rename, rm} from 'node:fs'

// Restore package.json from the backup we created
rename('package.temp.json', 'package.json', () => {})

// Delete the dist folder
rm('dist', {recursive: true}, () => {})
