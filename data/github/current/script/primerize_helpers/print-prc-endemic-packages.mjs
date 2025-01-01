import getEndemicPackages from "./endemic-packages.mjs"

const endemicPackages = await getEndemicPackages()

console.log(
  Array.from(endemicPackages.entries().map(([name, version]) => `${name}@${version}`)).join(' ')
)
