export const copilotSearchLogin = 'copilot'
export const copilotBotLogin = 'copilot-swe-agent'
export function isCopilot(login: string) {
  // need a more dynamic way to check if this is an "Assignable" agent
  return login.toLocaleLowerCase() === copilotBotLogin || login.toLocaleLowerCase() === copilotSearchLogin
}
