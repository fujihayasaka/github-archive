# Custom Agents

This directory contains custom agent definitions for the GitHub Copilot Coding Agent (sweagentd). Custom agents are specialized assistants that have domain-specific knowledge and can be invoked to perform specific tasks.

## Available Agents

### GenerateChangelog (`changelog.md`)
Generates changelog entries based on the last 24 hours of commit history. Reviews recent commits, fetches pull request descriptions, and creates properly formatted changelog entries following the project's style guidelines.

**Use when**: You need to update the changelog after merging PRs.

### Gopher (`gopher.md`)
A Go coding assistant specialized for testing and linting the sweagentd project. Helps fix tests, run linters, and write new tests following the project's Go conventions.

**Use when**: Working with Go code in the sweagentd backend.

### React (`react.md`)
Assists with React best practices and optimizations. Provides guidance on React patterns, hooks, performance optimization, and modern React development practices.

**Use when**: Working with React components in the runtime frontend.

### StaleFeatureFlagsFinder (`stale-feature-flags.md`)
Scans the codebase to identify stale feature flags based on Git history, usage patterns, and TODO comments. Generates prioritized reports with actionable recommendations for removing outdated flags.

**Use when**: You want to identify technical debt related to feature flags that may no longer be needed.

## Using Custom Agents

Custom agents can be invoked through the GitHub Copilot interface. When an agent is available for a specific task:

1. The agent will be suggested automatically based on your task context
2. You can explicitly request an agent by mentioning it in your prompt
3. The agent will analyze the codebase and provide recommendations or perform the requested task

## Adding a New Custom Agent

To add a new custom agent:

1. Create a new markdown file in this directory (e.g., `my-agent.md`)
2. Add YAML frontmatter with `name` and `description` fields:
   ```yaml
   ---
   name: MyAgent
   description: A brief description of what this agent does.
   ---
   ```
3. Write detailed instructions for the agent, including:
   - The agent's goal and purpose
   - Step-by-step process to follow
   - Guidelines and constraints
   - Expected output format
   - Examples and best practices

4. Follow the structure of existing agents for consistency

### Custom Agent Best Practices

- **Be specific**: Clearly define the agent's scope and responsibilities
- **Be thorough**: Include detailed instructions and examples
- **Be safe**: Agents should analyze and recommend, not make destructive changes
- **Be helpful**: Provide context about where to find relevant code and how to analyze it
- **Be consistent**: Follow the patterns established by existing agents

## Technical Details

Custom agents are loaded by the sweagentd runtime and become available as specialized tools. Each agent has its own context window and can be invoked independently to perform specific tasks.

The agent definitions in this directory are used to configure the behavior and capabilities of each custom agent.
