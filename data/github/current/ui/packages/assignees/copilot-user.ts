export function isCopilot(login: string) {
  // need a more dynamic way to check if this is an "Assignable" agent
  return login.toLocaleLowerCase() === 'copilot-swe-agent' || login.toLocaleLowerCase() === 'copilot'
}
