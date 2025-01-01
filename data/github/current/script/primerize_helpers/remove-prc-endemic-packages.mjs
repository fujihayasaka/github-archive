import {execSync} from 'child_process'
import getEndemicPackages from "./endemic-packages.mjs"

const endemicPackages = await getEndemicPackages()
const keys = Array.from(endemicPackages.entries().map(([name, _]) => `.dependencies."${name}"`))

execSync(`jq 'del(${keys.join(",")})' package.json > tmp.json && mv tmp.json package.json`)
