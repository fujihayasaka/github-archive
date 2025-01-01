# GUIDELINES

- NEVER work on the git master branch.
- When implementing changes (re-)use scratch space to create (or update) a plan and keep track of the implentation steps. See extra instructions in the rest of the file.
- Ensure something like `export PAGER=cat` in the terminal
- Be efficient with the terminal calls, combine them if possible
- Files in this package (`packages/issues`) are part of a Ruby on Rails application structured with packwerk.

- Make small atomic commits after a change. Before committing check if tests pass, rubocop linting is ok and sorbet typing pass. The scratch file should be in a separate commit, see extra instructions in the rest of the file.
- Tests should be run with `bin/rails test <file_name>`
- Linting errors should be checked and fixed with `bin/rubocop`
- Sorbet should be checked with `bin/srb`


# FEATURE FLAGS

- Feature flags should indicate the package and what is changing in a succinct manner.
- Feature flags can be added with:
  ```ruby
  if FeatureFlag.vexi.enabled?("<name>", <actor>, default: <boolean>)
    ...
  else
    ...
  end
  ```

  If a repository / repo is available in the context, use that as the actor. Actor is optional.

# SCRATCH

Use a scratch markdown file in `<git_root>/packages/issues/llm/scratch/` with the name of the branch.

When committing changes, the scratch file should be updated too, but commited in a separate commit with the message: `Updated <scratch_file_name>`.


# TESTS

Run tests with: `bin/rails test <file_name>`

# LINTING

Run rubocop with: `bin/rubocop`

# TYPE CHECKING / SORBET

Run Sorbet with: `bin/srb`
