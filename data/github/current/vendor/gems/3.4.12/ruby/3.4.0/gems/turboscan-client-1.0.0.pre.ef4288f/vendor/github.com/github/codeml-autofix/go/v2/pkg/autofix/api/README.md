## Go Autofix Integration Guide

#### Updated: June 2025


This guide explains how to integrate the Go Autofix library into your applications to generate fixes for code issues. The library provides flexible input options including direct SARIF content, file paths, or pre-extracted alerts.

### Table of Contents
- [Go Autofix Integration Guide](#go-autofix-integration-guide)
    - [Updated: June 2025](#updated-june-2025)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Integration Options](#integration-options)
  - [Using the API](#using-the-api)
    - [Creating an Autofixer Instance](#creating-an-autofixer-instance)
    - [Using Helper Functions](#using-helper-functions)
    - [Option 1: Working with SARIF Content](#option-1-working-with-sarif-content)
    - [Option 2: Working with SARIF Files](#option-2-working-with-sarif-files)
    - [Option 3: Direct Alert Processing](#option-3-direct-alert-processing)
  - [Additional Features](#additional-features)
    - [Previous Attempts](#previous-attempts)
    - [File Checksums](#file-checksums)
  - [Error Handling](#error-handling)
  - [Performance Considerations](#performance-considerations)
  - [Legacy API](#legacy-api)

### Overview
Go Autofix uses LLMs to suggest fixes for code issues identified in SARIF files. The library provides a flexible API that can be integrated into various environments:

- Server applications
- CI/CD pipelines
- Developer tools
- Command-line utilities

### Integration Options
There are two main ways to integrate with the Go Autofix library:

1. **Library Interface** (Recommended for Go services)
    - Direct, in-memory processing
    - Lower latency and overhead
    - Full control over resource management
  
2. **CLI Application** (For non-Go services or CI/CD)
    - Language-agnostic integration
    - Simpler for operational use cases
  
This guide focuses on the library interface.

### Using the API


#### Creating an Autofixer Instance

First, create an Autofixer instance that will handle all fix generation operations:

```go
import (
    "context"
    "time"
    "github.com/github/codeml-autofix/go/v2/pkg/autofix/api"
)

// Create a context with timeout for safety
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()

// Create the autofixer instance
options := &api.AutofixerOptions{
    ClientName: "my-client-name", // importing service identifier (e.g., "copilot-code-review")
    ModelName:  api.ModelProd,    // model name: ModelProd or ModelDev
    ModelConfig: &config.Config{
        CAPIProdKey: "your-prod-key",
        CAPIDevKey:  "your-dev-key",
    },
}

autofixer, err := api.NewAutofixer(ctx, options)
if err != nil {
    // Handle error
    return err
}

```

#### Using Helper Functions

For most use cases, using the specialized helper functions that provide a simple, clean API:

```go
import (
    "context"
    "github.com/github/codeml-autofix/go/v2/pkg/autofix/api"
)

// When you have alerts already
fix, err := autofixer.GenerateFixFromAlerts(
    ctx,
    alerts,         // []alerts.Alert - your pre-extracted alerts
    sourceFiles,    // map[string][]byte - source file contents
    "repo-id"       // repository identifier
)

// When you have SARIF content (bytes)
fix, err := autofixer.GenerateFixFromSarifContent(
    ctx,
    sarifContent,   // []byte - your SARIF JSON content
    sourceFiles,    // map[string][]byte - source file contents
    "repo-id"       // repository identifier
)

// When you have a SARIF file path
fix, err := autofixer.GenerateFixFromSarifFile(
    ctx, 
    sarifFilePath,  // string - path to your SARIF file
    sourceRoot,     // string - path to source code directory
    "repo-id",      // repository identifier
    nil             // optional file checksums
)
```

Please note that currently these helper functions only support dealing with a single alert at a time.


#### Option 1: Working with SARIF Content

Ideal for server applications that receive SARIF content and source files directly:

```go
// SARIF content and source files are already in memory
sarifContent := []byte(`{ "version": "2.1.0", ... }`) // Your SARIF JSON
sourceFiles := map[string][]byte{
    "src/main.go": []byte("package main\n\nfunc main() {..."),
    "src/utils.go": []byte("package main\n\nfunc helper() {..."),
}

// Generate fix using helper function
fix, err := autofixer.GenerateFixFromSarifContent(
    ctx,
    sarifContent,
    sourceFiles,
    "my-client-name",
    "owner/repo" 
)

if err != nil {
    return err
}
```

#### Option 2: Working with SARIF Files
Suitable for CLI tools or applications that have access to the filesystem:

```go
// Paths to SARIF file and source code
sarifFilePath := "/path/to/results.sarif"
sourceRoot := "/path/to/source/code"

// Generate fix using helper function
fix, err := autofixer.GenerateFixFromSarifFile(
    ctx,
    sarifFilePath,
    sourceRoot,
    "owner/repo", // repository ID (optional)
    nil           // optional file checksums
)

if err != nil {
    // Handle different error types
    return err
}
```

#### Option 3: Direct Alert Processing
For advanced use cases where alerts are already extracted:

```go
// Alerts are already extracted and processed
myAlerts := []alerts.Alert{...}
sourceFiles := map[string][]byte{...} // Optional source files for context

// Generate fix using helper function
fix, err := autofixer.GenerateFixFromAlerts(
    ctx,
    myAlerts,
    sourceFiles,
    "owner/repo" // repository ID (optional)
)

if err != nil {
    return err
}
```

### Additional Features 

#### Previous Attempts

The `PreviousAttempts` field allows you to provide context about previous fix attempts. This is useful for:

    - Requesting a new fix, if fix was not accepted,
    - Retrying after a failed fix, or
    - Helping the model avoid repeating unsuccessful approaches

```go
options := &api.AutofixerOptions{
    SarifFilePath: "/path/to/results.sarif",
    SourceRoot:    "/path/to/source/code",
    ClientName:    "my-client-name",
    PreviousAttempts: []fix.PreviousAttempt{
        {
            Diffs: []string{
                "diff --git a/src/main.go b/src/main.go\n...", 
            },
            ValidationErrors: []struct{
                ValidatorName   string `json:"validatorName"`
                ValidationError string `json:"validationError"`
            }{
                {
                    ValidatorName:   "CodeQL",
                    ValidationError: "Fix introduces a new SQL injection vulnerability",
                },
            },
        },
    },
}
autofixer, err := api.NewAutofixer(ctx, options)
if err != nil {
    return err
}
```

#### File Checksums
The FileChecksums field allows tracking file versions to ensure fixes are applied to the correct version:

```go
// You can provide checksums directly
checksums := map[string]string{
    "src/main.go": "a1b2c3d4e5f6...",
    "src/utils.go": "f6e5d4c3b2a1...",
}
options := &api.AutofixerOptions{
    ClientName:    "my-client-name",
    ModelName:     api.ModelProd,
    FileChecksums: checksums,
}

fix, err := autofixer.GenerateFixFromSarifFile(
    ctx,
    sarifFilePath,
    sourceRoot,
    "owner/repo",
    checksums
)
```

The library uses SHA-256 for file checksums. Here's how to generate compatible checksums:

Example:

```go
// CalculateFileChecksum generates a compatible checksum for file content
func CalculateFileChecksum(content []byte) string {
    h := sha256.New()
    h.Write(content)
    return fmt.Sprintf("%x", h.Sum(nil))
}
```

### Error Handling
The library returns structured errors via the `autofix.AutofixError` interface:

```go
fix, err := autofixer.GenerateFixFromSarifFile(ctx, sarifFilePath, sourceRoot, "repo-id", nil)
if err != nil {
    switch err.Type() {
    case autofix.ErrorTypeInvalidRequest:
        // Handle invalid input (e.g., missing required fields)
        log.Printf("Invalid request: %v", err)
    case autofix.ErrorTypeNotAutofixable:
        // Issue cannot be auto-fixed
        log.Printf("Not autofixable: %v", err)
    case autofix.ErrorTypeLogic:
        // Internal error
        log.Printf("Logic error: %v", err)
    case autofix.ErrorTypeContextCanceled:
        // Request was canceled or timed out
        log.Printf("Request canceled: %v", err)
    }
    return err
}
```

### Caching

The library supports caching model responses. This is being handled automatically
provided two conditions are satisfied:

- The `Cache` property of `AutofixerOptions` has been populated with a string
  containing a valid directory to be used by the caching layer of the library,
  and
- The model to be used supports the [`HashableModel`](../llm/models/types.go)
  interface. The models the library supports already support this interface by
  construction, but if you're passing in your own model you need to ensure it
  satisfies this interface.

Leaving the `Cache` property of `AutofixerOptions` empty means that a caching
layer won't be used over the base model - in effect disabling the cache (more
precisely, not enabling it).

### Performance Considerations

- In-memory processing (`go/pkg/autofix/codebase/memory_codebase.go`) for better performance 
- Each request consumes LLM resources, which can cause resource exhaustion if not managed properly
- The library is thread-safe but be mindful of concurrent request limits to LLM services
  

### Legacy API

```go
// Legacy approach (still supported but not recommended for new code)
fixer, err := api.NewSarifFixer(context.Background(), &api.Options{
    ClientName: "my-service",
    ModelName:  "capi-prod-4o",
})
if err != nil {
    // Handle error
}

fix, err := fixer.GenerateFix(ctx, sarifFilePath, sourceRoot, repoID, fileChecksums)
```

  
