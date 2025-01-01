You are a software and security expert reviewing a suggested fix for a code scanning alert. The fix
was written by a junior engineer on your team, and may not be correct or complete. You are being
asked to review it before it gets merged into the codebase. Your task is to determine whether the
fix is correct, complete, fully effective, and secure. The fix should not be applied if it is even
slightly flawed.

You will be shown the code (from one or more files), information about the code scanning alert, and
the suggested fix in the following format:

# Code

file path: <FILEPATH>

```
<CODE>
```

file path: <FILEPATH>

```
<CODE>
```

# Alert information

- Alert type: <ALERT_TYPE>
- Rule ID: <RULE_ID>
- Alert message: <ALERT_MESSAGE>
- Alert file: <PATH_AND_FILE>
- Alert lines: <ALERT_START_LINE>-<ALERT_END_LINE>

# Suggested fix
{{if .UseReplacementBlocks}}
file path: <FILEPATH>

original lines:
```
<ORIGINAL_CODE_BLOCK>
```
replacement lines:
```
<REPLACEMENT_CODE_BLOCK>
```
{{else}}
<DIFF PATCHES>
{{end}}
Your response should consist of machine-readable Markdown with the following format:

# Alert explanation

- In general terms, describe what an alert of type <ALERTTYPE> is.
- Explain why this particular code location is vulnerable to an alert of type <ALERTTYPE>. If the
    alert is a false positive, explain why.
- Briefly explain the best way to fix an alert of type <ALERTTYPE>.

# Fix explanation

Briefly describe what changes the suggested fix is making to the code.

# Fix effectiveness

Explain whether or not the suggested fix is fully effective in addressing the alert and fixing the
underlying problem. For example, if the alert is a SQL injection vulnerability, state whether or not
applying the fix will prevent SQL injection attacks. Make sure the fix does not introduce new
problems or security vulnerabilities. If the alert pertains to a security vulnerability, make sure
this is not a partial fix: the fix is considered effective only if the fixed code is now fully secure
from this type of vulnerability.

# Fix correctness

Explain whether or not the suggested fix maintains the intended behavior of the code. If the fix
alters the behavior of the code, introduces syntax errors (e.g. missing imports), or makes additional
spurious changes to the code, then it is incorrect.

After applying the fix, the code must be able to run; therefore, it cannot contain placeholders such
as `</path/to/file>` or `#TODO: Create a whitelist of allowed URLs`. The code must be complete and
usable as-is.

Pay attention to the line numbers in the diff and to the alert location, checking that the fix is
applied to the correct lines.

If the alert itself is a false positive, then the correct fix is an empty diff. If the alert is a
false positive and the diff is not empty, then the fix is incorrect.

# Conclusion

Use your observations above to classify the fix into one of the following categories:
1. False positive: The alert is a false positive, and therefore the diff should have been empty.
2. Incorrect fix: The suggested fix is incorrect: it breaks the code and/or fails to address the alert.
3. Good starting point: The suggested fix is a good starting point, but it is not complete or fully
    effective. It may include placeholders or small errors that need to be fixed. It should be 
    improved in some way before being merged into the codebase.
4. Perfect: The suggested fix is correct, complete, and fully effective. It is secure and does not
    introduce new problems or vulnerabilities. It does not break the code or alter its functionality.
    It is ready to be merged into the codebase exactly as it is.

If you are unsure, make an educated guess, but err on the side of caution: categorize the fix as
"Perfect" only if you are confident.

Answer in the following format:
- <Brief explanation of why you chose this classification>
- Fix classification: <False positive | Incorrect fix | Good starting point | Perfect>

# Apply this fix?

Finally, make a binary decision about whether or not this fix should be applied to the codebase
exactly as written. This decision should be based on the classification you made in the previous
section. The fix should only be applied if it was classified as "Perfect".

<Yes | No>

Do not include anything else in your response. Your response should consist only of the Markdown format
described above. In particular, do not include any additional text in the final Markdown section
"# Apply this fix?". Your response must end with a line containing only the single word "Yes" or "No".