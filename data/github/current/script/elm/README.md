# ELM Schema Validator

## Overview on the ELM Schema Validator script

The ELM Schema Validator ensures data consistency between protobuf API definitions from monolith-twirp-elm-* gems and database models in the GitHub monolith. It validates that ELM migration APIs in app/api/internal/twirp/elm/{team}/**.rb include all required database fields
and detects potential data drift issues before they reach production.

**📋 Service Extraction**: For teams extracting services from the monolith, see [Domain Isolation and Service Extraction](domain_isolation.md) for schema validation considerations.

## CI Validation Errors Guide

For how to fix validation errors check `script/elm/ci_validation_errors_guide.md`.

## CI Configuration

The ELM Schema Validator runs automatically on pull requests via GitHub Actions (`.github/workflows/elm-schema-validation.yml`). The CI behavior is controlled by a single environment variable:

### Production Readiness Toggle

```yaml
env:
  DO_NOT_FAIL_CI: true  # Set to false when ready for production
```

**Current Behavior (`DO_NOT_FAIL_CI: true`):**

- Validation runs on every PR touching ELM-related files
- Results are logged in CI output for visibility
- **Does not block CI** - PRs can merge even with validation failures
- **No PR comments posted** - avoids noise during testing phase

**Production Behavior (`DO_NOT_FAIL_CI: false`):**

- Validation runs and **blocks CI** on schema compatibility issues
- **Posts detailed PR comments** with fix instructions when validation fails
- Provides clear escalation path to @github/migrations-vnext-reviewers team

### Ready for Production Checklist

When the ELM Schema Validator has been thoroughly tested and is ready to enforce schema validation:

1. **Update the environment variable** in `.github/workflows/elm-schema-validation.yml`:

   ```yaml
   DO_NOT_FAIL_CI: false  # Enable production mode
   ```

2. **Verify current validation state** - ensure the validator passes in strict mode:

   ```bash
   bin/elm-schema-validator --strict
   ```

3. **Communicate the change** to the `migrations-vnext` team and #enterprise-live-migrations channel

4. **Monitor initial PRs** to ensure the validation feedback is helpful and actionable

This supports gradual rollout of schema validation enforcement.

### Error Categories

All schema differences are explicitly documented in `field_mappings.yml`:

- `known_gaps`: Protobuf fields not in DB (computed fields, GitHub.com-only IDs, etc.)
- `missing_required_fields`: DB fields missing from protobuf (to be added or mapped)
- `field_mappings`: Field name differences (`commit_sha` → `sha`)
- `compatibility_issues`: Export/import flow mismatches
- `dag_filtering`: DAG fields to ignore (`*_resource_id`)

## Quick Start

```bash
# Run validation with all configured suppressions (normal CI mode)
bin/elm-schema-validator

# Run validation showing ALL errors including those normally suppressed
bin/elm-schema-validator --strict

# Run tests
bin/rails test test/script/elm/elm_schema_validator_test.rb
```

## Command-Line Options

| Option | Description | Use Case |
|--------|-------------|----------|
| `--strict` / `-s` | Show ALL errors including those normally suppressed by configuration | Auditing complete schema drift state, understanding raw validation |

### Normal vs Strict Mode

**Normal Mode (default):**
- ✅ 0 errors, 5 warnings
- Uses all suppression configurations (known_gaps, missing_required_fields, etc.)
- Suitable for CI and day-to-day development
- Only shows actionable errors that need fixing

**Strict Mode (`--strict`):**
- ❌ 24 errors, 5 warnings
- Ignores ALL suppression configurations
- Shows complete picture of schema drift
- Useful for auditing and understanding the full validation state

### Programmatic Usage

```ruby
# Normal mode with configuration-based suppression
validator = ElmSchemaValidator.new(strict: false)
success = validator.validate!  # Returns true/false

# Strict mode showing all errors
validator = ElmSchemaValidator.new(strict: true)
success = validator.validate!  # Will likely return false showing all drift
```

## Files Structure

```
script/elm/
├── elm-schema-validator           # Main validation script
├── field_mappings.yml            # YAML configuration for field filtering and mapping
└── README.md                     # This comprehensive guide

bin/
└── elm-schema-validator          # Wrapper script for CLI usage

test/script/elm/
└── elm_schema_validator_test.rb  # Comprehensive test suite (17+ tests)

.github/workflows/
└── elm-schema-validation.yml    # CI workflow configuration
```

## Configuration

The validator uses `script/elm/field_mappings.yml` for comprehensive configuration:

### Field Mappings
Maps protobuf field names to database column names when they differ:
```yaml
field_mappings:
  commit_status_check:
    commit_sha: sha  # Protobuf uses commit_sha, database uses sha
```

### Known Gaps
Documents fields that exist in protobuf but not in database with business justification:
```yaml
known_gaps:
  commit_status_check:
    avatar_url: "Computed field, not stored in database"
    html_url: "Generated URL, not persisted"
```

### Model Mappings
Maps API types to their corresponding ActiveRecord model classes:
```yaml
model_mappings:
  commit_status_check: Status
  check_runs: CheckRun
  check_suites: CheckSuite
```

### DAG Field Filtering
Configurable filtering of DAG infrastructure fields that are used for dependency tracking between systems but not stored in core business tables:
```yaml
dag_filtering:
  ignore_suffixes:
    - "_resource_id"  # Filters repository_resource_id, check_suite_resource_id, etc.
  ignore_fields:
    - "resource_id"
    - "source_resource_id"
```

## Validation Types

The validator performs comprehensive schema validation across multiple dimensions:

### 1. Field Drift Detection

- **Purpose**: Identifies protobuf fields that don't exist in the database schema
- **Impact**: Prevents runtime errors when importing data with unknown fields
- **Fix**: Add field mappings, document as known gaps, or remove from protobuf

### 2. Required Field Validation

- **Purpose**: Ensures protobuf includes all database fields marked as required (NOT NULL constraints, presence validators)
- **Impact**: Prevents data integrity issues and database constraint violations
- **Fix**: Add missing fields to protobuf or document business justification

### 3. Export → Import Flow Compatibility

- **Purpose**: Validates that export APIs provide all fields that corresponding import APIs expect
- **Impact**: Ensures data can flow successfully from export to import without field loss
- **Fix**: Add missing fields to export API or remove unnecessary fields from import API

### 4. Model Mapping Validation

- **Purpose**: Ensures all discovered API types have corresponding ActiveRecord model mappings
- **Impact**: Enables proper validation against actual database schema
- **Fix**: Add model mappings to `field_mappings.yml` configuration

## Error Types & Solutions

When validation fails, errors are categorized for easy resolution:

- **📊 FIELD DRIFT ERRORS**: Protobuf fields not found in database
- **⚠️ REQUIRED FIELD ERRORS**: Required database fields missing from protobuf
- **❓ COMPATIBILITY ERRORS**: Export/import field mismatches
- **🗺️ MODEL MAPPING ERRORS**: API types without model mappings

Each error includes actionable suggestions pointing to specific fixes in `field_mappings.yml`.

### Testing Your Fixes

After making changes:

1. **Run the validator locally**:

   ```bash
   bin/elm-schema-validator
   ```

1. **Check specific APIs**:
   - Ensure error counts decrease
   - Verify warnings are addressed

### CI Integration

The validator runs automatically on pull requests via GitHub Actions:

```yaml
# .github/workflows/elm-schema-validation.yml
- name: Run ELM Schema Validation
  run: bin/elm-schema-validator
```

Returns exit code 1 on validation failures to fail CI builds.

### Development

#### Adding New APIs

When adding new ELM APIs, update the configuration in `script/elm/field_mappings.yml`:

1. **Add model mapping**:

   ```yaml
   model_mappings:
     your_new_api: YourActiveRecordModel
   ```

1. **Add field mappings** if protobuf uses different field names:

   ```yaml
   field_mappings:
     your_new_api:
       protobuf_field_name: database_column_name
   ```

1. **Document known gaps** with business justification:

   ```yaml
   known_gaps:
     your_new_api:
       computed_field: "Generated field, not stored in database"
   ```

1. **Run validation** to ensure compatibility:

   ```bash
   bin/elm-schema-validator
   bin/rails test test/script/elm/elm_schema_validator_test.rb
   ```

#### Debugging Validation Issues

The validator provides comprehensive output:

- **API Discovery**: Shows which import/export APIs were found
- **Model Mapping**: Displays API → ActiveRecord model relationships
- **Field Analysis**: Details missing/extra fields for each API
- **Categorized Errors**: Groups issues by type with specific fix suggestions
- **Known Gap Handling**: Shows which documented gaps are being skipped

Use quiet mode for automated checks:

```ruby
validator = ElmSchemaValidator.new(quiet: true)
success = validator.validate!
# Returns true/false, errors available in validator.errors
```
