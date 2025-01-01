# Rules

Rule definitions include information such as name, short/long
description, help, severity, tags, etc. They are embedded into Turboscan
and used to augment any rules received in SARIF from CodeQL or Rubocop.

## How to update the rules definitions

1. Copy the new rule data into `ts/sarif/ruledata/codeql.sarif` or `ts/sarif/ruledata/rubocop.sarif`

2. Run `script/setup && script/dev-run make cassettes` to update any tests that may rely on the rule help.

3. Open a PR!

## How to add rules definitions for a new tool

1. Copy the new rule data into `ts/sarif/ruledata`

2. Extend `ts/sarif/defaults.go` to embed the new rule file.
