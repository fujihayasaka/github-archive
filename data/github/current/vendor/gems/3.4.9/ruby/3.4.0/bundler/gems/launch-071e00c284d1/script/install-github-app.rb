if GitHub.launch_github_app.nil?
  system "script/create-github-app" or exit 1
end

if GitHub.launch_github_app.nil?
  raise "The Launch app doesn't exist :("
end

nwo = ARGV[0]
repo = Repository.nwo(nwo)
raise "Repo not found: #{nwo.inspect}" if repo.nil?

if IntegrationInstallation.with_repository(repo).where(integration_id: GitHub.launch_github_app.id).present?
  puts "Already installed!"
else
  puts "Installing the app."
  result = GitHub.launch_github_app.install_on(repo.owner, repositories: [repo], installer: repo.owner)
  p result
  exit 1 unless result.success?
end

puts "Disabling auto-triggered check suites."
repo.set_auto_trigger_checks(actor: repo.owner, app: GitHub.launch_github_app, value: false)
