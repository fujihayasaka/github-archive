# SandboxView

The SandboxView component renders a sandboxed iFrame that then gets served content by the viewscreen service.
The component then handles messaging with the iFrame to set the desired content and report any errors.

**Note**: Rendering HTML/JS/CSS in the browser is a serious security risk. Don't use this component or pattern unless
your use case has been cleared by the product security team.
