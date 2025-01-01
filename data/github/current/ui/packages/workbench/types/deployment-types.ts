// Client-side reflection of enum in model at packages/copilot/app/models/spark/runtime_app.rb
export const DeploymentVisibility = {
  OnlyOwner: 'only_owner',
  GitHub: 'github',
} as const

export type DeploymentVisibility = (typeof DeploymentVisibility)[keyof typeof DeploymentVisibility]
