package model

import "github.com/github/launch/types"

// Configuration is a parsed workflow file
type Configuration struct {
	// Actions are all of the Actions referenced from `using:` steps in the workflows
	Actions []*Action

	// Workflows represents a workflow listening to a single trigger
	Workflows []*Workflow
}

// Action represents a single "action" used in a workflow
type Action struct {
	Identifier string
	Uses       Uses
}

// Workflow represents a single workflow
type Workflow struct {
	Identifier        string
	RunNameExpression string
	Path              string
	On                On
	File              types.ResolvedFile
	FileReference     types.WorkflowFileReference
}

// Job represents one job in a workflow with an optional strategy
type Job struct {
	ID          string
	Name        *string
	Needs       []string
	Strategy    *Strategy
	Environment *Environment
}

// IsMatrix returns true if the job is a matrix job
func (j *Job) IsMatrix() bool {
	return j.Strategy != nil && j.Strategy.Matrix != nil
}

// IsStrategyExpression returns true if the job has a strategy defined as an expression
func (j *Job) IsStrategyExpression() bool {
	return j.Strategy != nil && j.Strategy.Expression != ""
}

// Strategy holds the Matrix info or an expression
type Strategy struct {
	Matrix     *Matrix
	Expression string
}

// Matrix represents the values for a matrix
type Matrix any

// Environment points to a deployment environment
type Environment struct {
	Name      string
	IsDynamic bool
}
