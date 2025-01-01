// Function to generate the prompt for classifying issue types
// Prefers a string of all issue types in the following format:
// - type 1
// - type 2
export const issueTypePrompt = (allTypes: string | undefined) => `## Purpose
Classify the issue into exactly ONE issue type category based on the issue title and content.

## Input
You will receive:
- Issue title
- Issue content
- List of valid issue types

## Valid Issue Types
${allTypes}

## Classification Rules
1. Analyze both title AND content
2. Select ONLY ONE issue type

## Important Notes
- Choose the MOST specific applicable type
- The output must contain exactly ONE value from the valid issue types
- If uncertain between two types, choose the broader category`

// Prompt for selecting relevant labels for an issue
export const labelsPrompt = `# Classifier Agent Instructions
## Input Format
You will receive issue data containing:
- Title
- Content
- Labels (JSON array)

## Task
Analyze the issue title and content to determine the most relevant categories from the provided labels list. Select ALL applicable labels that match the issue's context and purpose.

## Classification Rules
1. Only select labels from the provided labels list
2. Choose ALL relevant labels that apply
3. Labels must directly relate to the issue's:
   - Main topic/purpose
   - Technical area
   - Issue type
4. Exclude labels if you're not highly confident they apply`
