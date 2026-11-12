Generate a .github/copilot-instructions.md file in the repository that contains instructions that tell GitHub Copilot coding agent how to work in the codebase like a developer would after acquiring a fresh clone for the first time. For example: how to build, test, run, and navigate in the code as well as the locations of any important or frequently visited parts of the codebase.

The instructions should start with a firm directive to always follow the instructions and only fallback to additional search and context gathering if the information in the instructions is incomplete or found to be in error.

# Guidelines to Follow
- Instructions should be imperative in tone: "Run [this command]", "Do not do [this]".
- Run and validate every command before adding it to the instructions.
- Be EXHAUSTIVE in your validation of the instructions: your goal is to create instructions that anyone can copy pasted and have just work, EVERY time.
- ***ALWAYS*** validate that EVERY command works before adding it to the instructions.
  - If a command does not work, document it in the instructions. For example: "npm install -- fails due to firewall limitations".
- ***NEVER CANCEL BUILDS OR LONG-RUNNING COMMANDS***. Wait for ALL builds and commands to finish during your validation. If a build takes more than 30 minutes, that is NORMAL - document the expected time in the instructions.
- ***CRITICAL***: Set appropriate timeouts (60+ minutes) for all build commands. DO NOT use default timeouts that may cause premature cancellation.
- ***MANUAL VALIDATION REQUIREMENT***: After building and running the application, you MUST test actual functionality by running through complete user scenarios. Simply starting and stopping the application is NOT sufficient validation. Execute real workflows that a user would perform.
- DO NOT skip to publishing instructions that have not been validated to work correctly. If you have not validated that an instruction does work, AND you have exhausted EVERY alternative, only then should you document it as "does not work".
  - It is better to keep trying different approaches repeatedly than give instructions that do not work.
  - Take as much time as you need, be thorough in your inventory of the repository, and your instructions.
- Be concise. Prioritize relevant details (e.g.: commands that are validated to work) instead of verbose language or formatting.
- Write the instructions to encourage the agent to always to do known working validation steps.

# Questions the Instructions Should Answer
The instructions should answer questions that will save the agent time and missteps, including but not limited to:
- **CRITICAL**: What are the exact timeout values and timing expectations for builds and tests? Always include "NEVER CANCEL" warnings with specific time estimates.
- Are we able to build and run the code? For example: "The build succeeds and we can run it with a local DB using npm run dev but must use the test user account, ABC. Always build and exercise your changes." or "Do not try to build the code, it only builds on Windows.".
- **VALIDATION SCENARIOS**: What specific user scenarios should be tested after making changes? For example: "Always test the login flow by creating a user, logging in, and performing a basic action" or "Test the CLI by running `./tool --help` then `./tool process sample.txt` and verify the output file is created correctly."
- What are the EXACT URIs and commands I should run to install all required SDKs and dependencies. For example: "Always download NodeJS with `wget https://nodejs.org/dist/v22.17.1/node-v22.17.1-linux-x64.tar.xz`".
- What are the EXACT COMMANDS I should run to build? For example: "install NodeJS and then run `npm install` and then `npm run build:cli` to build".
- How do I run the unit tests? For example: "Run `npm install && npm run test` to run the tests".
- How long does each common step or command usually take? For example: "NEVER CANCEL: Build takes 45 minutes. Test suite takes 15 minutes. Wait for completion."
- Include EXPLICIT timeout values and cancellation warnings for all time-consuming operations.
- What additional validation steps should the coding agent run to ensure that the change will pass the CI build. For example: "always run `npx run lint` before committing your change".
- What are the key projects in this codebase?

# Example Instructions File
```markdown
# Graphing calculator
Graphing calculator is an HTML5, CSS, and TS web application that is packaged and distributed as both a website (foo-calculator.com) and an Electron desktop application for Windows, Linux, and Mac OS.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively
- Bootstrap, build, and test the repository:
  - `apt-get install build-essential`
  - `./configure`
  - `build_wasm_modules.sh`
  - `install_nodejs.sh`
  - `npm install`
  - `npm run build` -- takes 45 minutes to complete. NEVER CANCEL. Set timeout to 60+ minutes.
- `make test` -- takes 15 minutes. NEVER CANCEL. Set timeout to 30+ minutes.
  - `npm run test`
- Run the web app:
  - ALWAYS run the bootstrapping steps first.
  - Client: `npm run dev`
  - Server: `npm run server`
- Run the Electron app:
  - `install_electron.sh`
  - Debug the worker: `npm run appstart`
  - Debug the UI: `npm run appdev`

## Validation
- Always manually validate any new code via Playwright when changing the NodeJS web application.
- ALWAYS run through at least one complete end-to-end scenario after making changes.
- You can build and run the Electron version of the application, however, you cannot interact with its UI.
- Always run `npm run format` and `npm run lint` before you are done or the CI (.github/workflows/build.yml) will fail.

## Common tasks
The following are outputs from frequently run commands. Reference them instead of viewing, searching, or running bash commands to save time.

### Repo root
ls -a [repo-root]
.
..
README.md
configure
package.json
src
build_wasm_modules.sh
install_nodejs.sh
install_electron.sh
CONTRIBUTING.md
CHANGELOG.md

### cat README
cat README.md
<omitted for brevity>

### cat package.json
cat package.json
<omitted for brevity>
```

# Steps to Follow
- Perform a comprehensive inventory of the codebase. Search for and view:
  - README.md, CONTRIBUTING.md, and all other documentation files.
  - Search the codebase for build steps and indications of workarounds like 'HACK', 'TODO', etc.
  - All scripts, particularly those pertaining to build and repo or environment setup. e.g.: build.sh, configure, and npm scripts.
  - All build and actions pipelines. e.g.: GitHub workflows.
  - All project files. e.g.: package.json and csproj.
  - All configuration and linting files.
  - All resource definitions. e.g.: ARM and terraform templates.
- **MEASURE BUILD TIMES**: Time every single build and test command you run. Document the actual time taken and add 50% buffer for the timeout recommendations.
- For each question:
  - Search EXHAUSTIVELY for an answer.
  - Validate the correctness of your answer, EXHAUSTIVELY.
  - **SCENARIO VALIDATION**: Run and exercise an application scenario to ensure that your instructions are sufficient to get it fully operational. Make sure you can take a screenshot of the running application, if the application type and tools support it.
  - **Include explicit "NEVER CANCEL" warnings and timeout values** for any command that takes more than 2 minutes.
  - Record the answer in the instructions using an imperative tone. Remember, your goal is to generate instructions that the coding agent will follow.
- think: are there other pieces of information that will enable the agent to complete common tasks with fewer incorrect bash commands or less search?
  - Record this information in the instructions. For example: "Always check handler.ts after making changes to apiContracts.ts."
</StepsToFollow>

# CRITICAL REMINDER:
- ***NEVER CANCEL ANY BUILD OR TEST COMMAND*** - Builds may take 45+ minutes, tests may take 15+ minutes
- Set explicit timeouts of 60+ minutes for build commands and 30+ minutes for test commands
- DO NOT stop long running commands or builds. Build may take 45 minutes or more. Use long timeouts.
- If a command appears to hang, wait at least 60 minutes before considering alternatives
- DO NOT skip validation because it is taking too long or did not work at first.
