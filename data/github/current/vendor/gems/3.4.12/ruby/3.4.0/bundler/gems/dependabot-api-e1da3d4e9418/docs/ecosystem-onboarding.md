# Ecosystem Onboarding Automation

This document describes how to use the ecosystem onboarding automation tool to streamline the process of adding a new package ecosystem to dependabot-api.

## Overview

The `ecosystem:onboard` Rake task automates the repetitive file changes required when onboarding a new ecosystem. It updates protobuf definitions, feature flags, beta registration, config parsing, and schema files.

## Usage

```bash
rake ecosystem:onboard[ecosystem_name,package_manager_name,mode]
```

### Parameters

- **ecosystem_name** (required): The name of the ecosystem as it appears in config files (e.g., 'conda', 'uv', 'helm')
- **package_manager_name** (optional): The package manager name if different from the ecosystem name (defaults to ecosystem_name)
- **mode** (optional): Operation mode - one of:
  - `interactive` (default): Prompts for confirmation before each change
  - `overwrite`: Automatically overwrites all files without prompting
  - `skip`: Skips all file changes (dry-run mode)

### Examples

```bash
# Basic usage with interactive mode (default)
rake ecosystem:onboard[conda]

# Specify a different package manager name
rake ecosystem:onboard[npm,npm_and_yarn]

# Overwrite mode - no prompts
rake ecosystem:onboard[uv,,overwrite]

# Skip mode - see what would change without making changes
rake ecosystem:onboard[helm,,skip]
```

## What Gets Automated

The tool performs the following changes:

1. **Protobuf Enum Update** (`proto/dependabot-api/twirp/dependabot_api.proto`)
   - Adds the ecosystem to the `PackageEcosystem.Name` enum
   - Assigns the next available ID

2. **Beta Registration** (`lib/ecosystems.rb`)
   - Adds the ecosystem to `Ecosystems::BETA` array
   - Adds constant to `PackageManagers::ALL`

3. **File Regex Pattern** (`lib/ecosystem_file_regex.rb`)
   - Adds a new method for the ecosystem's file patterns
   - Includes a TODO comment for adding actual patterns

4. **Config Parsing** (`app/actions/parse_config_file.rb`)
   - Adds the ecosystem to `PACKAGE_MANAGER_LOOKUP` hash

5. **JSON Schema** (`config/config_file_json_schema.json`)
   - Adds the ecosystem to the `package-ecosystem` enum
   - Creates a schema definition for the ecosystem

## Manual Steps After Running

After the automated changes, you'll need to complete the following manual steps:

1. **Update File Patterns**: Edit the generated `*_regex` method in `lib/ecosystem_file_regex.rb` to add the correct file patterns for your ecosystem

2. **Regenerate Protobuf Code** (if protobuf was updated):
   ```bash
   script/protoc
   ```

3. **Bump Gem Version**: Update the version in `gen/ruby/lib/proto/dependabot-api/version.rb`

4. **Language Mapping** (optional): Add language mapping to `Ecosystems::PACKAGE_MANAGER_LANGUAGE_MAPPING` in `lib/ecosystems.rb`

5. **Advisory Database Mapping** (optional): Add mapping to `Advisorydb::PACKAGE_MANAGERS` in `lib/ecosystems.rb` if the ecosystem has security advisories

6. **Run Tests**: Ensure all tests pass with your changes

7. **Update Documentation**: Update any relevant documentation in the repository

8. **Create PRs/Releases**: If protobuf was regenerated, create necessary PRs and releases for the updated code

## Output

The tool provides:
- Real-time progress updates as it makes changes
- A summary of all changes made
- A list of manual steps that still need completion
- Additional notes and recommendations

## Testing the Tool

You can test the onboarding tool without making changes using skip mode:

```bash
rake ecosystem:onboard[test_ecosystem,,skip]
```

## Example Output

```
=== Ecosystem Onboarding Tool ===
Ecosystem: conda
Package Manager: conda
Mode: interactive
==================================================

Add CONDA to protobuf enum in proto/dependabot-api/twirp/dependabot_api.proto? [y/N] y
✓ Added CONDA to protobuf enum with ID 26

Add CONDA to Ecosystems::BETA array in lib/ecosystems.rb? [y/N] y
✓ Added PackageManagers::CONDA to BETA array

...

==================================================
SUMMARY
==================================================

✓ Changes made:
  - Added CONDA = 26 to protobuf enum
  - Added PackageManagers::CONDA to Ecosystems::BETA array
  - Added conda_regex method to EcosystemFileRegex
  - Added "conda" => PackageManagers::CONDA to PACKAGE_MANAGER_LOOKUP
  - Added conda to package-ecosystem enum
  - Added conda schema definition

⚠ Manual steps required:
  1. Run 'script/protoc' to regenerate Twirp Ruby code
  2. Bump gem version in gen/ruby/lib/proto/dependabot-api/version.rb
  3. Create PRs/releases for regenerated protobuf code

📝 Additional notes:
  - Review all TODO comments in the generated code
  - Update file patterns in EcosystemFileRegex#conda_regex
  - Run tests to ensure everything works correctly
  - Update documentation as needed

✓ Onboarding complete!
```

## Related Documentation

- [Adding a New Ecosystem Guide](https://github.com/github/dependabot-updates/blob/main/docs/development/version-updates/adding-a-new-ecosystem.md)
- Example PR: [UV API onboarding](https://github.com/github/dependabot-api/pull/6345)
