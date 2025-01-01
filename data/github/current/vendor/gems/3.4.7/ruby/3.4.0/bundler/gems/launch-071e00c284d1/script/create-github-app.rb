require Rails.root + 'script/create-launch-github-app'

def create_app
  log "Creating app ..."
  client = CreateLaunchGitHubApp.new
  app = client.create_app
  client.enable_hooks
  app
end

def update_app
  return unless app = GitHub.launch_github_app
  log "Updating app '#{app.name}' (#{app.id}). (Run with '--force' to recreate this app.)"
  client = CreateLaunchGitHubApp.new
  app = client.update_app
  client.enable_hooks
  app
end

def destroy_app
  return unless app = GitHub.launch_github_app
  log "Destroying app ..."
  CreateLaunchGitHubApp.new.destroy_app
end

def config(app:)
  <<~TXT
    GITHUB_APP_ID="#{app.id}"
    GITHUB_SECRETS_APP_RELAY_ID="#{app.global_relay_id}"
    ACTIONS_APP_RELAY_ID="#{app.next_global_id}"
    GITHUB_APP_PRIVATE_KEY="#{CreateLaunchGitHubApp.new.get_private_key.gsub("\n", "\\n")}"
    GITHUB_APP_BOT_NODE_ID="#{app.bot.global_relay_id}"
  TXT
end

def log(*message)
  $stderr.puts(*message)
end

unless Rails.env.development?
  log "This can only be run in the development environment!"
  exit 1
end

app = update_app || create_app

# output the config (used to populate launch/tmp/github-app)
File.write(Rails.root + "tmp/launch-github-app", config(app: app))
