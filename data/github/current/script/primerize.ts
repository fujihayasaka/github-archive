import path from 'path'
import fs from 'fs'
import readline from 'readline'
const { promisify } = require('util')
import { exec as cpExec, spawn } from 'child_process'
import yargs, {Argv} from 'yargs'
const chalk = require('chalk')
import ora, {Ora} from 'ora'
const prompt = require('prompt-sync')({sigint: true})
const exec = promisify(cpExec)

const PAT_DOCS_URL = 'https://gh.io/primerize-pat-setup'

// Paths
const githubWorkspacePath = '/workspaces/github'
const primerWorkspacePath = '/workspaces/primer'

const defaultRepo = 'primer/react'

const printColors = {
  loading: chalk.white,
  log: chalk.dim,
  success: chalk.green,
  warn: chalk.yellow,
  error: chalk.red,
  info: chalk.blue,
}

type PrimerizeArgs = {
  verbose: boolean
}

type SetupArgs = PrimerizeArgs & {
  repo: string
}

type ResetArgs = PrimerizeArgs & {
  repo: string
}

type StartArgs = PrimerizeArgs & {
  repo: string
  watch: boolean
}

type CanaryArgs = PrimerizeArgs & {
  prUrl: string
}

type TokenArgs = PrimerizeArgs & {
  repo: string
}

type RepoInfo = {
  name: string,
  workspaceDirectory: string,
  mainBranch: string
}

type RepoConfig = RepoInfo & {
  postInstallCallback?: (repoInfo: RepoInfo) => Promise<void>
  start: (args: StartArgs, repoInfo: RepoInfo) => Promise<void>
  stop: () => Promise<void>
  canary?: (args: CanaryArgs, repoInfo: RepoInfo) => Promise<void>
}

// Repos
const repos: Record<string, RepoConfig> = {
  'primer/react': {
    name: 'primer/react',
    workspaceDirectory: path.join(primerWorkspacePath, 'react'),
    mainBranch: 'main',
    postInstallCallback: async (repoInfo: RepoInfo) => {
      // Move to the repo's location
      await print(`Moving to ${repoInfo.workspaceDirectory}`, {behavior: 'append', level: 'log'})
      process.chdir(repoInfo.workspaceDirectory)

      // Execute script/setup
      try {
        const spinner = await print(`Executing script/setup...`, {level: 'loading'})
        await exec('script/setup')
        await print(`✅ Executed script/setup successfully`, {behavior: 'replace', level: 'success', spinner})
      } catch (error) {
        exitWithError(`❌ Error while running script/setup: ${(error as Error).message}`)
      }

      // Move to github/github
      await print(`Moving to ${githubWorkspacePath}`, {behavior: 'append', level: 'log'})
      process.chdir(githubWorkspacePath)

      let nonPersistedPackages = ''
      try {
        const spinner = await print(`Gathering non-persisted packages...`, {level: 'loading'})
        const {stdout} = await exec('node script/primerize_helpers/print-prc-endemic-packages.mjs')
        nonPersistedPackages = stdout

        await print(`✅ Non-persisted packages gathered`, {behavior: 'replace', level: 'success', spinner})
        await print(`Non-persisted packages:\n${nonPersistedPackages.split(' ').join('\n')}`)
      } catch (error) {
        exitWithError(`❌ Error while running script/setup: ${(error as Error).message}`)
      }

      try {
        const spinner = await print(`Running NPM install on primer/react with non-persisted packages...`, {level: 'loading'})
        await exec(`npm install /workspaces/primer/react/packages/react ${nonPersistedPackages}`)

        await print(`✅ Installed primer/react with non-persisted packages`, {behavior: 'replace', level: 'success', spinner})
      } catch (error) {
        exitWithError(`❌ Error while NPM install on primer/react: ${(error as Error).message}`)
      }

      try {
        const spinner = await print(`Updating git indices...`, {level: 'loading'})
        await exec('git update-index --assume-unchanged $(git ls-files node_modules/@primer/react)')

        await print(`✅ Updated git indices`, {behavior: 'replace', level: 'success', spinner})
      } catch (error) {
        exitWithError(`❌ Error while updating git indices: ${(error as Error).message}`)
      }

      await print(`\n🎉 Primer React setup successfully!\n`, {level: 'success'})
    },
    start: async (args, repoInfo: RepoInfo) => {
      process.chdir(path.join(repoInfo.workspaceDirectory, 'packages', 'react'))

      const childArgs = ['rollup', '-c']
      if (args.watch) childArgs.push('-w')
      childArgs.push('--no-watch.clearScreen')

      const child = spawn('npx', childArgs, {stdio: 'inherit'})
      child.on('error', (err) => {
        console.error(`Failed to start process: ${err.message}`)
      })

      // Exit the parent process with the same exit code as the child
      child.on('close', (code) => process.exit(code))
    },
    stop: async () => {
      await print(`Moving to ${githubWorkspacePath}...`)
      process.chdir(githubWorkspacePath)

      let spinner = await print(`Resetting NPM modules...`, {level: 'loading'})
      await exec(`node script/primerize_helpers/remove-prc-endemic-packages.mjs`)
      await print(`✅ NPM modules reset`, {behavior: 'replace', level: 'success', spinner})

      spinner = await print(`Resetting version of primer/react...`, {level: 'loading'})
      const primerPkgJson = JSON.parse(fs.readFileSync(`${githubWorkspacePath}/npm-workspaces/primer/package.json`, {encoding: 'utf-8'}))
      const prcVersion = primerPkgJson.dependencies["@primer/react"]
      await exec(`npm i @primer/react@${prcVersion}`)
      await exec("npm uninstall @primer/react")
      await exec(`npm i @primer/react@${prcVersion} -w npm-workspaces/primer`)
      await print(`✅ primer/react installed successfully`, {behavior: 'replace', level: 'success', spinner})

      spinner = await print(`Checking out Primer workspace...`, {level: 'loading'})
      await exec(`git checkout -- "${githubWorkspacePath}/npm-workspaces/primer"`)
      await exec("git checkout package-lock.json node_modules/@primer/react")
      await print(`✅ Primer workspace checked out`, {behavior: 'replace', level: 'success', spinner})

      spinner = await print(`Installing NPM packages...`, {level: 'loading'})
      await exec(`npm i`)
      await print(`✅ NPM packages installed`, {behavior: 'replace', level: 'success', spinner})

      spinner = await print(`Updating git indices...`, {level: 'loading'})
      await exec("git update-index --no-assume-unchanged $(git ls-files node_modules/@primer/react)")
      await print(`✅ Updated git indices`, {behavior: 'replace', level: 'success', spinner})

      await print(`\n🎉 De-primerized successfully\n`, {level: 'success', spinner})
    },
    canary: async function(args: CanaryArgs, repoInfo: RepoInfo) {
      let spinner = await print("Querying status checks to determine canary version", {level: 'loading'})

      const output = (await exec(`gh pr checks ${args.prUrl} --json name,description`)).stdout as string
      const checks = JSON.parse(output) as Array<{name: string, description: string}>
      const [owner, repo] = repoInfo.name.split('/')
      const re = new RegExp(`Published @?${owner}\/${repo}`)
      const publishedCheck = checks.find((elem) => re.test(elem.name))

      if (!publishedCheck) {
        await print('Could not find canary version in status checks', {level: 'error', spinner})
        return
      }

      const canaryVersion = publishedCheck.description
      await print(`✅ Found canary version ${canaryVersion}`, {level: 'success', behavior: 'replace', spinner})

      const prcPath = '/workspaces/github/node_modules/@primer/react'

      if (fs.lstatSync(prcPath).isSymbolicLink()) {
        const rl = readline.createInterface({
          input: process.stdin,
          output: process.stdout,
        })

        await print(
          '\n\n***************************' +
          '\nYou are currently using a local copy of primer/react, i.e. you ran `bin/primerize setup`. ' +
          'Installing a canary version of primer/react requires running `bin/primerize reset` to ' +
          'revert your environment back to the way it was.' +
          '\n***************************\n\n'
        )

        // prevent readline from consuming the previous print statement
        process.stdout.write("\n")

        const undo = await new Promise<boolean>((resolve) => {
          rl.question('Undo local primerize changes? (y/n): ', answer => {
            if (/[Yy]e?s?/.test(answer)) {
              resolve(true)
            } else {
              resolve(false)
            }

            rl.close()
          })
        })

        if (undo) {
          await this.stop()
        } else {
          await print('Aborting\n', {level: 'error'})
          return
        }
      }

      // Move to github/github
      await print(`Moving to ${githubWorkspacePath}`, {behavior: 'append', level: 'log'})
      process.chdir(githubWorkspacePath)

      spinner = await print('Installing canary version of primer/react', {level: 'loading'})
      await exec(`npm i @primer/react@${canaryVersion} -w npm-workspaces/primer`)
      await print('✅ Canary version installed', {level: 'success', behavior: 'replace', spinner})

      await print(`\n🎉 Done\n`, {level: 'success'})
    },
  }
}

let argv = {
  verbose: true
}

// Args
yargs
  .option('verbose', {
    alias: 'v',
    description: 'Verbose Output',
    default: false,
    type: 'boolean'
  })
  .command<SetupArgs>('setup [repo]', 'Setup workspace for a Primer repo',
  (args: Argv) => {
    return args.positional('repo', {
      describe: 'The Primer repository you wish to work with',
      default: defaultRepo
    })
  },
  async (args) => {
    argv.verbose = args.verbose

    if (args.verbose) {
      await print('Verbose Mode', {level: 'info'})
    }

    const repoConfig = getRepoConfig(args.repo)

    if(repoConfig) {
      await setupPrimerWorkspace()
      // Clone or pull Primer code
      await cloneOrPullPrimerRepository(repoConfig)

      // Automatically configure the Primer PAT during setup
      await setupGitToken(repoConfig)

      // Call the post install callback if available
      await repoConfig.postInstallCallback?.(repoConfig)
    }

    const shouldOpenWorkspace = prompt(`Would you like to open ${repoConfig?.name} in your workspace? (y/n)`, 'y')
    if(['yes', 'y'].includes(shouldOpenWorkspace)) {
      await exec(`code -a ${repoConfig?.workspaceDirectory}`)
    }
  })
  .command<StartArgs>('start [repo]', 'Compile a Primer repo',
    (args) => {
      args.positional('repo', {
        describe: 'The Primer repository you wish to compile',
        default: defaultRepo
      })

      args.option({
        'w': {
          alias: 'watch',
          default: true,
          describe: 'Watches for changes and recompiles',
          type: 'boolean'
        }
      })
      return args
    },
    async (args) => {
      argv.verbose = args.verbose

      const repoConfig = getRepoConfig(args.repo)
      await repoConfig?.start(args, repoConfig)
    }
  )
  .command<ResetArgs>({
    command: 'reset [repo]',
    aliases: ['stop'],
    describe: 'Resets a Primer repo back to NPM version',
    builder: (args) => {
      args.positional('repo', {
        describe: 'The Primer repository you wish to reset',
        default: defaultRepo
      })
      return args
    },
    handler: async (args) => {
      argv = args
      const repoConfig = getRepoConfig(args.repo)
      await repoConfig?.stop()
    }
  })
  .command<TokenArgs>({
    command: 'git-setup [repo]',
    describe: `Sets up the local git to use your Primer PAT. See ${PAT_DOCS_URL} to get started.`,
    builder: (args) => {
      args.positional('repo', {
        describe: 'The Primer repository to be configured to use $PRIMER_TOKEN for git authentication',
        default: defaultRepo
      })
      return args
    },
    handler: async (args) => {
      argv.verbose = args.verbose
      const repoConfig = getRepoConfig(args.repo)

      if (repoConfig) {
        await setupGitToken(repoConfig)
      }
    }
  })
  .command<CanaryArgs>(
    'canary <prUrl>',
    'Installs the latest canary version for the given Primer pull request',
    (args) => {
      return args.positional('prUrl', {
        describe: 'The URL to the Primer pull request',
      })
    },
    async (args) => {
      argv.verbose = args.verbose

      const match = args.prUrl.match(/github\.com\/(\w+)\/(\w+)\/pull\/(\d+)/)

      if (!match) {
        await print('Could not identify owner, repo, and pull request ID from provided URL', {level: 'error'})
        return
      }

      const [_, owner, repo, prId] = Array.from(match)
      const nameWithOwner = `${owner}/${repo}`
      const repoConfig = getRepoConfig(nameWithOwner)

      if (!repoConfig?.canary) {
        await print(`Repo ${nameWithOwner} does not support the canary subcommand`)
        return
      }

      await repoConfig.canary(args, repoConfig)
    }
  )
  .help()
  .argv

type PrintLevel = 'loading' | 'log' | 'success' | 'warn' | 'error' | 'info'
type PrintBehavior = 'append' | 'replace'
type PrintOptions = {behavior?: PrintBehavior; level?: PrintLevel, spinner?: Ora}

async function print(message: string, {behavior = 'append', level = 'log', spinner = ora()}: PrintOptions = {} ): Promise<Ora|undefined> {
  if(argv.verbose) {
    await process.stdout.write('\n')
    await process.stdout.write(printColors[level](message))
  } else if(['loading', 'error', 'success', 'info'].includes(level)) {
    if(behavior === 'append')
      await process.stdout.write('\n')

    if(level === 'loading') {
      spinner.start()
      spinner.text = message
      spinner.color = 'blue'
      return spinner
    }

    await spinner.stop()
    if (behavior === 'replace') {
      await spinner.clear()
      await process.stdout.clearLine(0)
      await process.stdout.cursorTo(0)
    }
    await process.stdout.write(printColors[level](message))
  }
  return
}

async function exitWithError(message: string) {
  await print(message,{level: 'error'})
  yargs.exit(1, new Error(message))
}

async function setupPrimerWorkspace () {
  if (!fs.existsSync(primerWorkspacePath)){
    fs.mkdirSync(primerWorkspacePath)
  }
  await print('✅ Primer workspace directory created', {level: 'success'})
}

function getRepoConfig (repoName: string): RepoConfig | undefined {
  // Check if we have a configuration for the repo specified
  if(!repos[repoName])
    exitWithError(`❌ No configuration defined for '${repoName}'. Valid options are: ${Object.keys(repos).join(', ')}.`)
  else
    return repos[repoName]
}

async function cloneOrPullPrimerRepository (repo: RepoConfig) {
  // Clone and pull @primer/react
  process.chdir(primerWorkspacePath)

  if (!fs.existsSync(repo.workspaceDirectory)){
    const spinner = await print(`Repo ${repo.name} hasn't been cloned, cloning...`, {level: 'loading'})
    try {
      await print(`gh repo clone ${repo.name}`)
      await exec(`gh repo clone ${repo.name}`)
      await print(`✅ Cloned ${repo.name} successfully`, {behavior: 'replace', level: 'success', spinner})
    } catch (error) {
      spinner?.stop()
      exitWithError(`❌ Error while cloning repository: \n ${(error as Error).message}`)
    }
  } else {
    const spinner = await print(`Repo ${repo.name} is cloned, pulling latest...`, {level: 'loading'})
    try {
      await print(`Moving to ${repo.workspaceDirectory}...`)
      process.chdir(repo.workspaceDirectory)
    } catch (error) {
      spinner?.stop()
      exitWithError(`❌ Error while moving to ${repo.workspaceDirectory}: \n ${(error as Error).message}`)
    }
    try {
      await print(`Pulling '${repo.mainBranch}' branch...`)
      await exec(`git pull origin ${repo.mainBranch}`)
      await print(`✅ Pulled '${repo.mainBranch}' branch successfully`, {behavior: 'replace', level: 'success', spinner})

    } catch (error) {
      spinner?.stop()
      exitWithError(`❌ Error while pulling '${repo.mainBranch}' branch: \n ${(error as Error).message}`)
    }
  }
}

async function setupGitToken(repo: RepoConfig) {
  if (fs.existsSync(repo.workspaceDirectory)) {
    try {
      await print(`Moving to ${repo.workspaceDirectory}...`)
      process.chdir(repo.workspaceDirectory)
    } catch (error) {
      exitWithError(`❌ Error while moving to ${repo.workspaceDirectory}: \n ${(error as Error).message}`)
    }
  }

  try {
    const spinner = await print(`Setting up ${repo.name} Git remote with Primer PAT...`, {level: 'loading'})
    const primerEnvToken = process.env.PRIMER_TOKEN

    if (primerEnvToken) {
      // we need to first add an empty string to the local credential helper config so that Git doesn't use the system-level credential helper
      // (git explicitly uses an empty string here to tell it to ignore the system-level, don't ask me why)
      // we are also using --replace-all to replace any previous credential helpers that might have been set by previous executions of this script
      await exec(`git config --local --replace-all credential.helper ""`)
      // then we can set the credential helper to our custom helper which makes use of the $PRIMER_TOKEN environment variable
      await exec(`git config --local --add credential.helper "/workspaces/github/script/primerize_helpers/gitcredentials.sh"`)
      await print(`✅ ${repo.name} remote push access configured using $PRIMER_TOKEN from Codespace Secrets!\n`, {behavior: 'replace', level: 'success', spinner})
    } else {
      await print(`ℹ️ Primer PAT not set in Codespace Secrets. See ${PAT_DOCS_URL} for information on how to push changes to ${repo.name}\n`, {behavior: 'replace', level: 'info', spinner})
    }
  } catch (error) {
    exitWithError(`❌ Error while setting up ${repo.name} Git remote: ${(error as Error).message}. See ${PAT_DOCS_URL} for more info.`)
  }
}
