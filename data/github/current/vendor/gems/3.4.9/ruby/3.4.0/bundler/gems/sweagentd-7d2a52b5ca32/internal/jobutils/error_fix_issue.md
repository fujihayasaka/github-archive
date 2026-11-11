@{{ .Login }} Unfortunately I hit an unexpected error while trying to work on issue #{{.IssueNumber }}. I've automatically reported this to GitHub.

You can ask me to try again later by unassigning and then reassigning the issue to me again.

If you want to contact GitHub about this error, please mention the following identifier so they can better serve you: `{{ .RequestID }}`

Sorry for the inconvenience!

{{.Telemetry}}