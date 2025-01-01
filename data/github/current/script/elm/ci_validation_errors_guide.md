
# CI Validation Errors Guide

**🚨 Got a validation error? Start here for quick fixes! 🚨**

This section provides comprehensive solutions for all types of schema validation errors.

### Error Categories

All schema differences are explicitly documented in `field_mappings.yml`:

- `known_gaps`: Protobuf fields not in DB (computed fields, GitHub.com-only IDs, etc.)
- `missing_required_fields`: DB fields missing from protobuf (to be added or mapped)
- `field_mappings`: Field name differences (`commit_sha` → `sha`)
- `compatibility_issues`: Export/import flow mismatches
- `dag_filtering`: DAG fields to ignore (`*_resource_id`)

#### 📊 Field Drift Errors

**Problem**: Protobuf API defines fields that don't exist in the database schema.

**Root Cause**: The ELM protobuf definitions include fields that were removed/renamed in the database.

**Example**:
```
❌ Missing in DB: resource_id, repository_resource_id, head_sha, check_suite_resource_id
```

**Solution**:

1. **Remove/rename fields from protobuf**:
   - Clone the `github/migrations-vnext` repo (see "Working with Protobuf Definitions" below)
   - Edit the protobuf definitions in the `migrations-vnext` repository in `internal/proto/elm`
   - Deprecate the fields from the message definitions
   - Regenerate and publish the ELM gem using `make build-protobufs`
   - Commit your changes.
   - If you changed proto files in `internal/proto/elm/{your-team}` then there is a `monolith-twirp-elm-{your-team}` gem that will be updated with the new definitions.

2. **Update export/import handlers**:
   - Update the `monolith-twirp-elm-{team}` gem in the monolith to get the new proto definitions
   - Modify the export/import logic in `app/api/internal/twirp/elm/{your-team}/v1/` to handle these changes. The tests for your export/import handlers will check if the new definitions work as expected or whether you need to make further changes.

---

#### ⚠️ Required Field Errors

**Problem**: Database has required fields (NOT NULL constraints or presence validators) that are missing from the protobuf API.

**Root Cause**: The protobuf definitions are incomplete and don't include all required database fields.

**Example**:
```
⚠️ Missing in API: repository, check_suite_id, github_app_id, repository_id
```

**Solutions**:
1. **Add missing required fields to protobuf**:
   - Clone the `github/migrations-vnext` repo (see "Working with Protobuf Definitions" below)
   - Edit the protobuf definitions in the `migrations-vnext` repository in `internal/proto/elm`
   - Add the missing required fields as `optional` or `repeated` as appropriate
   - Ensure correct field types (string, int32, int64, bool, etc.)
   - Regenerate and publish the ELM gem using `make build-protobufs`
   - Commit your changes.
   - If you changed proto files in `internal/proto/elm/{your-team}` then there is a `monolith-twirp-elm-{your-team}` gem that will be updated with the new definitions.

2. **Update export/import handlers**:
   - Update the `monolith-twirp-elm-{team}` gem in the monolith to get the new proto definitions
   - Modify the export/import logic in `app/api/internal/twirp/elm/{your-team}/v1/` to handle these changes. The tests for your export/import handlers will check if the new definitions work as expected or whether you need to make further changes.

---

#### ❓ Export → Import Flow Compatibility Errors

**Problem**: Export API doesn't provide all fields that Import API expects, breaking the data flow.

**Root Cause**: Mismatched field definitions between export and import protobuf messages.

**Example**:
```
❌ check_runs: Missing source_resource_id
❌ commit_status_check: Missing avatar_url, source_resource_id
```

**Solutions**:
1. **Add missing fields to Export API**:
   - Clone the `github/migrations-vnext` repo (see "Working with Protobuf Definitions" below)
   - Edit the protobuf definitions in the `migrations-vnext` repository in `internal/proto/elm`
   - Add the missing fields that Import API expects
   - Regenerate and publish the ELM gem using `make build-protobufs`
   - Commit your changes.
   - If you changed proto files in `internal/proto/elm/{your-team}` then there is a `monolith-twirp-elm-{your-team}` gem that will be updated with the new definitions.
   - Go back to the github/github repo
   - Ensure the export handler in the monolith populates these fields

2. **Remove unnecessary fields from Import API**:
   - Following the same process above, if fields aren't actually needed, remove them from import protobuf
   - Regenerate the gem
   - Update import handler in the monolith to not expect these fields

---

#### 🗺️ Model Mapping Errors

**Problem**: API types discovered but no corresponding ActiveRecord model mapping defined.

**Root Cause**: New API types added without updating the validator's model mapping logic.

**Example**:
```
❌ Unmapped (3): actions_settings, repository_settings, settings
```

**Solution - add model mappings to validator**:
- Edit `script/elm/field_mappings.yml`
- Add entries to the `model_mappings` section
- Map API types to their corresponding ActiveRecord models

**Example Fix**:
```yaml
model_mappings:
  commit_status_check: Status
  check_run: CheckRun  # Add new mapping
```

---

### ⚠️ Warnings (Non-blocking)

**Problem**: Various issues that don't break functionality but indicate best practices violations.

**Types**:
1. **Unparseable protobuf patterns**: Message definitions that don't match expected patterns
2. **Extra fields in Export API**: Fields exported but not used by Import API
3. **Model mapping warnings**: Skipped validations due to missing models

**Solutions**:
1. **Clean up protobuf definitions**:
   - Fix message patterns to match expected formats
   - Remove unused fields or document why they're needed

2. **Address model mapping issues**:
   - Add missing model mappings (see Model Mapping Errors above)

---

## Working with Protobuf Definitions

### Repository Setup for Protobuf Changes

**Important**: The ELM protobuf definitions are maintained in a separate repository. To make changes to protobuf schemas:

1. **Clone the migrations-vnext repository in your Codespace**:

   ```bash
   cd /workspaces
   gh repo clone github/migrations-vnext
   cd migrations-vnext
   script/bootstrap
   ```

2. **Make protobuf changes**:
   - Edit `.proto` files in `internal/proto/elm` folder in the `migrations-vnext` repository
   - Follow the existing patterns for message definitions
   - Ensure field types and names match your schema requirements

3. **Test and publish changes**:

   ```bash
   # In migrations-vnext repository
   make build-protobufs
   ```

   This will update your `monolith-twirp-elm-{your-team}` gem.

4. **Update gems in `github/github`**:
   - Once new ELM gems are published, update `Gemfile` in this repository
   - Run `bin/bundle update` to get the latest protobuf definitions
   - Re-run `bin/elm-schema-validator` to verify fixes

### Common Protobuf Fix Workflows

#### Fixing Export/Import Compatibility Issues

When you see errors like:
```
❌ commit_status_check: Export API missing fields that Import API expects: avatar_url, source_resource_id
```

**Root Cause**: The export protobuf definition doesn't include all fields that the import protobuf expects.

**Solution Process**:

1. **In migrations-vnext repository**: Add missing fields to the export protobuf definition
2. **In github/github repository**: Update the export handler to populate the new fields
3. **Test the fix**: Update gems and re-run `bin/elm-schema-validator`

**Example Fix for commit_status_check**:

In `migrations-vnext` export protobuf definition, ensure these fields are present:
```protobuf
message ExportCommitStatusCheck {
  // ... existing fields ...
  string avatar_url = 15;
  string source_resource_id = 16;
}
```

In `github/github` export handler (`export_commit_status_checks_api_handler.rb`):
```ruby
def build_status_check_hash(status)
  {
    # ... existing fields ...
    avatar_url: status.creator&.avatar_url || "",
    source_resource_id: status.id.to_s
  }
end
```
