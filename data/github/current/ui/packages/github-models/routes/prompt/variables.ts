// These are the well-known variables we currently support. Eventually this should expand to be dynamic, but for
// now this is it.

/** Input to the prompt */
export const VariableInput = 'input'

/** Ground truth, expected data */
export const VariableExpected = 'expected'

/** Expanded (=any referenced variables are resolved) prompt */
export const VariablePrompt = 'prompt'

/** Completion from the model for the expanded prompt */
export const VariableCompletion = 'completion'
